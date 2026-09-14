//
//  PersonalStressModel.swift
//  Tempo
//
//  本机训练的「个人压力回归模型」— 用 MoodEntry 含 features + Borg 主观标签
//  做 closed-form ridge regression(无外部依赖,纯 Swift 矩阵运算)。
//
//  Why ridge regression(不是 LSTM / RF):
//   - 闭式解 β = (XᵀX + λI)⁻¹ Xᵀy,O(d³),d=特征数 < 10,几毫秒搞定
//   - 完全本机,完全可解释(看权重就知道哪个特征影响最大)
//   - 30-100 个样本足以收敛
//   - Fitbit Body Response 本质也是「classical ML」非 deep,有先例
//
//  样本要求:
//   - 至少 30 个含 Borg label 的 MoodEntry
//   - 训练时 80/20 切 train/val,报 RMSE
//

import Foundation
import SwiftData
import TempoCore

@MainActor
@Observable
final class PersonalStressModel {
    static let shared = PersonalStressModel()

    // MARK: - Model state

    /// 训练好的权重(intercept + 7 features),nil = 未训练
    private(set) var weights: [Double]?
    /// 训练集 RMSE
    private(set) var trainRMSE: Double = 0
    /// 验证集 RMSE — 用户应当看这个评估模型质量
    private(set) var valRMSE: Double = 0
    /// 训练时样本数
    private(set) var sampleCount: Int = 0
    /// 训练时间
    private(set) var trainedAt: Date?
    /// 特征均值 / stddev — predict 时用同样的 normalization
    private(set) var featureMeans: [Double] = []
    private(set) var featureStddevs: [Double] = []

    private let modelKey = "tempo.personalStressModel.v1"

    private init() {
        loadFromDisk()
    }

    // MARK: - Feature engineering

    /// 把 MoodEntry 转成训练样本(features, label)
    /// 特征(6 维):hr / hrv / rr / hour_sin / hour_cos / age
    /// label:borgSubjective * 10(0-100,等价 stress 量级)
    ///
    /// 设计说明:sleep / strain 不作为特征,因为 mood log 时刻没法
    /// 可靠回溯当时的 daily strain 和昨晚 sleep — 留着会变成 0 噪声。
    /// 这些信号通过 evaluator base 已经反映,ML 只在「同等生理 + 同等时段
    /// + 同等年龄下,用户主观感受偏差」上拟合个性化校正。
    static let featureDimension: Int = 6
    static func extractTrainingSample(_ entry: MoodEntry) -> (features: [Double], label: Double)? {
        guard let borg = entry.borgSubjective,
              let hr = entry.hrAtLog, hr > 0 else { return nil }

        let hrv = entry.hrvAtLog ?? 50
        let rr = entry.rrAtLog ?? 14

        // 时段的圆形编码(sin/cos),让模型理解周期性
        let hour = Double(Calendar.current.component(.hour, from: entry.timestamp))
        let hourSin = sin(hour / 24.0 * 2 * .pi)
        let hourCos = cos(hour / 24.0 * 2 * .pi)

        let age = Double(entry.ageAtLog ?? 30)

        let features: [Double] = [hr, hrv, rr, hourSin, hourCos, age]
        let label = Double(borg) * 10   // 0-10 → 0-100

        return (features, label)
    }

    /// Predict 路径用同样的特征工程 — 调用方传 hr/hrv/rr/age 自己算 sin/cos
    static func buildFeatures(hr: Double, hrv: Double, rr: Double, at: Date, age: Int) -> [Double] {
        let hour = Double(Calendar.current.component(.hour, from: at))
        return [
            hr,
            hrv,
            rr,
            sin(hour / 24.0 * 2 * .pi),
            cos(hour / 24.0 * 2 * .pi),
            Double(age)
        ]
    }

    // MARK: - Training

    /// 从 SwiftData 拉所有 Borg-labelled MoodEntry 训练
    /// 返回 (success, message)
    func train(context: ModelContext) -> (success: Bool, message: String) {
        var descriptor = FetchDescriptor<MoodEntry>(
            sortBy: [SortDescriptor(\MoodEntry.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        guard let entries = try? context.fetch(descriptor) else {
            return (false, "无法读取 MoodEntry")
        }

        let samples = entries.compactMap { Self.extractTrainingSample($0) }
        guard samples.count >= 30 else {
            return (false, "样本不足(\(samples.count) / 30),请继续每天记录情绪 + 主观感受")
        }

        // 80/20 切分
        let shuffled = samples.shuffled()
        let splitIdx = Int(Double(shuffled.count) * 0.8)
        let train = Array(shuffled.prefix(splitIdx))
        let val = Array(shuffled.dropFirst(splitIdx))

        // 计算 feature normalization stats(用 train 集)
        let featureDim = train[0].features.count
        var means = [Double](repeating: 0, count: featureDim)
        var stddevs = [Double](repeating: 1, count: featureDim)
        for d in 0..<featureDim {
            let col = train.map { $0.features[d] }
            means[d] = col.reduce(0, +) / Double(col.count)
            let variance = col.reduce(0.0) { $0 + ($1 - means[d]) * ($1 - means[d]) } / Double(col.count)
            stddevs[d] = max(0.01, variance.squareRoot())
        }

        // 标准化 + 加 bias 项
        let xTrain = train.map { normalize($0.features, means: means, stddevs: stddevs) }
        let yTrain = train.map { $0.label }
        let xVal = val.map { normalize($0.features, means: means, stddevs: stddevs) }
        let yVal = val.map { $0.label }

        // Ridge regression closed-form
        guard let w = ridgeRegression(x: xTrain, y: yTrain, lambda: 1.0) else {
            return (false, "训练矩阵奇异,样本可能太相似")
        }

        // 算 RMSE
        let trainRmse = computeRMSE(x: xTrain, y: yTrain, weights: w)
        let valRmse = val.isEmpty ? trainRmse : computeRMSE(x: xVal, y: yVal, weights: w)

        // 保存
        self.weights = w
        self.trainRMSE = trainRmse
        self.valRMSE = valRmse
        self.sampleCount = train.count
        self.trainedAt = Date()
        self.featureMeans = means
        self.featureStddevs = stddevs
        saveToDisk()

        let qualityHint: String
        if valRmse < 15 { qualityHint = "模型表现优秀" }
        else if valRmse < 25 { qualityHint = "模型表现良好" }
        else { qualityHint = "样本需更多元化" }

        return (true, "训练完成(\(train.count) 样本,验证 RMSE \(String(format: "%.1f", valRmse)) — \(qualityHint))")
    }

    // MARK: - Predict

    /// 用模型预测 stress score(0-100)。未训练 / 样本不够 → nil
    func predict(features: [Double]) -> Double? {
        guard let w = weights, w.count == features.count + 1 else { return nil }
        let normalized = normalize(features, means: featureMeans, stddevs: featureStddevs)
        let withBias = [1.0] + normalized
        var yHat: Double = 0
        for (wi, xi) in zip(w, withBias) {
            yHat += wi * xi
        }
        return max(0, min(100, yHat))
    }

    var isTrained: Bool { weights != nil && (weights?.count ?? 0) > 0 }

    /// 「可以用」的置信门槛:val RMSE < 20 才信
    var isConfident: Bool { isTrained && valRMSE < 20 }

    // MARK: - Math helpers

    private func normalize(_ x: [Double], means: [Double], stddevs: [Double]) -> [Double] {
        zip(zip(x, means), stddevs).map { (pair, sd) in (pair.0 - pair.1) / sd }
    }

    /// closed-form ridge regression: β = (XᵀX + λI)⁻¹ Xᵀy
    /// X 是 [n × d] 已标准化,要自动加 bias 列。返回 (d+1) 维 weights(第 0 是 intercept)。
    private func ridgeRegression(x: [[Double]], y: [Double], lambda: Double) -> [Double]? {
        let n = x.count
        guard n > 0, n == y.count else { return nil }
        let d = x[0].count

        // 加 bias 列 → X 是 n × (d+1)
        let xb: [[Double]] = x.map { [1.0] + $0 }
        let p = d + 1   // 总参数数

        // XᵀX (p × p)
        var xtx = [[Double]](repeating: [Double](repeating: 0, count: p), count: p)
        for i in 0..<p {
            for j in 0..<p {
                var s: Double = 0
                for k in 0..<n {
                    s += xb[k][i] * xb[k][j]
                }
                xtx[i][j] = s
            }
        }
        // 加 λI(bias 项不正则化,index 0 跳过)
        for i in 1..<p {
            xtx[i][i] += lambda
        }

        // Xᵀy (p)
        var xty = [Double](repeating: 0, count: p)
        for i in 0..<p {
            var s: Double = 0
            for k in 0..<n {
                s += xb[k][i] * y[k]
            }
            xty[i] = s
        }

        // 解 xtx · β = xty → 用 Gauss-Jordan elimination(p ≤ 9,可以手撕)
        return gaussJordanSolve(a: xtx, b: xty)
    }

    /// 解线性方程组 a·x = b,a 是 p×p,b 是 p 维
    private func gaussJordanSolve(a inA: [[Double]], b inB: [Double]) -> [Double]? {
        var a = inA
        var b = inB
        let n = b.count
        for i in 0..<n {
            // partial pivot
            var pivotRow = i
            var maxPivot = abs(a[i][i])
            for k in i+1..<n where abs(a[k][i]) > maxPivot {
                pivotRow = k
                maxPivot = abs(a[k][i])
            }
            if maxPivot < 1e-12 {
                return nil  // 奇异
            }
            if pivotRow != i {
                a.swapAt(i, pivotRow)
                b.swapAt(i, pivotRow)
            }
            let pivot = a[i][i]
            for j in i..<n {
                a[i][j] /= pivot
            }
            b[i] /= pivot
            for k in 0..<n where k != i {
                let factor = a[k][i]
                for j in i..<n {
                    a[k][j] -= factor * a[i][j]
                }
                b[k] -= factor * b[i]
            }
        }
        return b
    }

    private func computeRMSE(x: [[Double]], y: [Double], weights: [Double]) -> Double {
        guard !x.isEmpty else { return 0 }
        var sum: Double = 0
        for i in 0..<x.count {
            let xb = [1.0] + x[i]
            var yHat: Double = 0
            for (wi, xi) in zip(weights, xb) {
                yHat += wi * xi
            }
            let diff = y[i] - yHat
            sum += diff * diff
        }
        return (sum / Double(x.count)).squareRoot()
    }

    // MARK: - Persistence

    private struct StoredModel: Codable {
        let weights: [Double]
        let featureMeans: [Double]
        let featureStddevs: [Double]
        let trainRMSE: Double
        let valRMSE: Double
        let sampleCount: Int
        let trainedAt: Date
    }

    private func saveToDisk() {
        guard let w = weights, let trained = trainedAt else { return }
        let stored = StoredModel(
            weights: w,
            featureMeans: featureMeans,
            featureStddevs: featureStddevs,
            trainRMSE: trainRMSE,
            valRMSE: valRMSE,
            sampleCount: sampleCount,
            trainedAt: trained
        )
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: modelKey)
        }
    }

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: modelKey),
              let stored = try? JSONDecoder().decode(StoredModel.self, from: data) else { return }
        self.weights = stored.weights
        self.featureMeans = stored.featureMeans
        self.featureStddevs = stored.featureStddevs
        self.trainRMSE = stored.trainRMSE
        self.valRMSE = stored.valRMSE
        self.sampleCount = stored.sampleCount
        self.trainedAt = stored.trainedAt
    }

    /// 清掉模型(用户主动 reset)
    func reset() {
        weights = nil
        featureMeans = []
        featureStddevs = []
        trainRMSE = 0
        valRMSE = 0
        sampleCount = 0
        trainedAt = nil
        UserDefaults.standard.removeObject(forKey: modelKey)
    }
}
