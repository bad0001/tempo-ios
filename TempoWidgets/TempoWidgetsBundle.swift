//
//  TempoWidgetsBundle.swift
//  TempoWidgets
//

import WidgetKit
import SwiftUI

@main
struct TempoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TempoWidgets()
        RecoveryWidget()
        #if !os(watchOS)
        TempoWidgetsLiveActivity()
        #endif
    }
}
