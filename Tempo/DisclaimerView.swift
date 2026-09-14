//
//  DisclaimerView.swift
//  Tempo
//

import SwiftUI

struct DisclaimerView: View {
    @AppStorage("disclaimerAccepted") private var accepted = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)
                .padding(.top, 60)

            Text("使用前须知")
                .font(.title.weight(.semibold))

            VStack(alignment: .leading, spacing: 18) {
                DisclaimerRow(
                    icon: "heart.text.square",
                    title: "非医疗设备",
                    text: "Tempo 提供的压力评估、心率分析仅供个人参考,不能替代专业医疗建议或诊断。"
                )

                DisclaimerRow(
                    icon: "lock.shield",
                    title: "健康原始数据留在本机",
                    text: "心率、血氧、睡眠等 HealthKit 原始记录默认只在设备处理。开启共振关怀时会发送压力摘要;HRV 数值与时间只有在你单独开启同步后才会上传。"
                )

                DisclaimerRow(
                    icon: "person.badge.shield.checkmark",
                    title: "如有不适请就医",
                    text: "若你出现持续胸痛、晕厥或其他异常症状,请立即停止使用并就医。"
                )
            }
            .padding(.horizontal, 28)

            Spacer()

            Button {
                accepted = true
                dismiss()
            } label: {
                Text("我已阅读并同意")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.pink, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .interactiveDismissDisabled()
    }
}

struct DisclaimerRow: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(.pink)
                .font(.title3)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(title))
                    .font(.headline)
                Text(LocalizedStringKey(text))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    DisclaimerView()
}
