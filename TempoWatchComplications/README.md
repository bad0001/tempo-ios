# Tempo Watch Complications — Xcode 加 Target 操作指南

## 为什么需要这一步?

Apple **不允许** 同一个 Widget Extension 同时被 iOS App 和 Watch App embed —— 我们已经实测过会报:
```
This target is built for watchOS Simulator but contains embedded content
(TempoWidgetsExtension.appex) built for iOS Simulator, which is not allowed.
```

所以表盘 complications **必须是独立的 watchOS-only Widget Extension target**。Swift 代码、Info.plist、entitlements 我都已经写好放在这个文件夹里;你只要在 Xcode 加一个 target 把它们关联进去就行。

---

## 5 步 Xcode 操作

### 步骤 1:打开项目
```
open Tempo.xcodeproj
```

### 步骤 2:加新 Target
- 菜单:**File → New → Target...**
- 选 **watchOS** 标签 → **Widget Extension**
- 点 **Next**

### 步骤 3:填配置
| 字段 | 值 |
|------|------|
| Product Name | `TempoWatchComplications` |
| Team | `TL7ZJMF9VQ`(刘辰奕 / Ayipocket) |
| Organization Identifier | `com.ayipocket` |
| Bundle Identifier | (自动) `com.ayipocket.tempo.watchkitapp.TempoWatchComplications` |
| Language | Swift |
| Include Live Activity | ❌ 不勾 |
| Embed in Application | **Tempo Watch App Watch App** ← 重要 |

点 **Finish**。

### 步骤 4:删 Xcode 自动生成的样板文件,关联我准备好的文件

Xcode 会自动创建 `TempoWatchComplications/` 子文件夹和几个文件,**全部删除**:
- `TempoWatchComplications.swift`
- `AppIntent.swift`(如果有)
- `TempoWatchComplicationsControl.swift`(如果有)
- `TempoWatchComplicationsLiveActivity.swift`(如果有)
- `Info.plist`(Xcode 自动生成的那个)
- `TempoWatchComplications.entitlements`(如果有)
- 整个 `Assets.xcassets`(可选保留)

然后右键 `TempoWatchComplications` group → **Add Files to "Tempo"...**:
- 文件:选我们当前 `TempoWatchComplications/` 文件夹下的 3 个文件:
  - `WatchComplications.swift`
  - `Info.plist`
  - `TempoWatchComplications.entitlements`
- ✅ 勾 **Copy items if needed** = **关闭**(因为文件已经在正确位置)
- ✅ 勾 **Create groups**
- ✅ **Add to targets** 只勾 `TempoWatchComplications`

### 步骤 5:设置 Build Settings

选 `TempoWatchComplications` target → **Build Settings** 标签:

| Key | Value |
|-----|------|
| `CODE_SIGN_ENTITLEMENTS` | `TempoWatchComplications/TempoWatchComplications.entitlements` |
| `INFOPLIST_FILE` | `TempoWatchComplications/Info.plist` |
| `SUPPORTED_PLATFORMS` | `watchos watchsimulator` |
| `TARGETED_DEVICE_FAMILY` | `4` |
| `WATCHOS_DEPLOYMENT_TARGET` | `10.0` |

切到 **General** 标签:
- **Frameworks and Libraries** 点 + → 选 `TempoCore`(SPM)

---

## 验证

```bash
cd /Volumes/Ayipocket/Tempo
xcodebuild -scheme Tempo -destination 'generic/platform=watchOS Simulator' build
```

应当看到 `** BUILD SUCCEEDED **`。

如果失败,常见问题:
- ❌ `TempoCore not found` → 步骤 5 加 framework 没成功,重新选 + TempoCore
- ❌ `NSExtensionPointIdentifier missing` → Info.plist 路径错,核对 INFOPLIST_FILE 设置
- ❌ Code signing failed → DEVELOPMENT_TEAM 填错,确认是 TL7ZJMF9VQ

---

## 完成后用户体验

1. iPhone 安装 Tempo + Watch 同步 App 装好
2. 打开 Apple Watch 表盘,长按 → **编辑** → 滑到 **Complications** 那页
3. 点任意 complication 位置 → 滚动找 **Tempo 压力 / Tempo 恢复 / Tempo 节奏**
4. 三种 complication 都支持 4 个 family:
   - **Circular**(圆形小位)
   - **Rectangular**(矩形长条)
   - **Inline**(顶部一行)
   - **Corner**(角度位,Series 6+)

5. 数据来自 iPhone 主 App 推送的 `SharedSnapshotStore` JSON 文件(`group.com.ayipocket.tempo`),iPhone 端 `HomeView.loadHKData` 完成时同时:
   - 写 App Group 文件 → Watch / iOS Widget 一起读
   - WC `updateApplicationContext` → Watch App TabView 读

---

## 设计要点

- **15min 刷新一次** — watchOS budget 限制,过频会被系统降频
- **共享 WatchSnapshot DTO** — Codable JSON,加新字段不破坏老 widget
- **没数据时显示「—」+「打开 App 同步」** — graceful degradation
- **体温警示** stress complication 的 rectangular family 会显示「体温偏高」chip

---

## 三个 Widget 内容

| Widget kind | 显示 | Family |
|------------|------|-------|
| `StressComplication` | 压力分 + 等级 + 体温警示 | Circular / Rect / Inline / Corner |
| `RecoveryComplication` | 恢复分 + 等级 + 负荷 chip | Circular / Rect / Inline / Corner |
| `TempoIndexComplication` | 一行看完:压力 + 恢复 + 心率 | Rect / Inline |
