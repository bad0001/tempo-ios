//
//  TempoWidgetsLiveActivity.swift
//  TempoWidgets
//

#if !os(watchOS)
import ActivityKit
import WidgetKit
import SwiftUI
import TempoCore

struct TempoWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BreathingActivityAttributes.self) { context in
            BreathingLockScreenView(
                attributes: context.attributes,
                state: context.state
            )
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "wind")
                            .foregroundStyle(.mint)
                        Text(context.attributes.patternName)
                            .font(.subheadline.weight(.medium))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.completedCycles) / \(context.attributes.targetCycles)")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.phaseLabel)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(phaseColor(context.state.phase))
                        Spacer()
                        Text("\(context.state.remainingSeconds) s")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                    }
                }
            } compactLeading: {
                Image(systemName: "wind")
                    .foregroundStyle(.mint)
            } compactTrailing: {
                Text("\(context.state.remainingSeconds)s")
                    .monospacedDigit()
                    .foregroundStyle(phaseColor(context.state.phase))
            } minimal: {
                Image(systemName: "wind")
                    .foregroundStyle(.mint)
            }
        }
    }
}

struct BreathingLockScreenView: View {
    let attributes: BreathingActivityAttributes
    let state: BreathingActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "wind")
                    .foregroundStyle(.mint)
                Text(attributes.patternName)
                    .font(.headline)
                Spacer()
                if state.isFinished {
                    Text("完成")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Text("\(state.completedCycles) / \(attributes.targetCycles) 循环")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(state.phaseLabel)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(phaseColor(state.phase))
                Spacer()
                Text("\(state.remainingSeconds)")
                    .font(.system(size: 56, weight: .ultraLight, design: .rounded))
                    .monospacedDigit()
                Text("秒")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }
}

func phaseColor(_ phase: String) -> Color {
    switch phase {
    case "inhale": .mint
    case "hold1": .yellow
    case "exhale": .blue
    case "hold2": .indigo
    default: .gray
    }
}
#endif
