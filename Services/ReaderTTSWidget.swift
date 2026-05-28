// ReaderTTSWidget.swift
// SwiftUI layouts for Lock Screen and Dynamic Island Live Activities.

import ActivityKit
import WidgetKit
import SwiftUI

#if canImport(ActivityKit)
struct ReaderTTSWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReaderTTSActivityAttributes.self) { context in
            // Lock Screen and Notification Center UI
            HStack(spacing: 16) {
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 24))
                    .foregroundColor(.orange)
                    .frame(width: 48, height: 48)
                    .background(Color.orange.opacity(0.12), in: .circle)
                
                VStack(alignment: .leading, spacing: 4) {
                    if let novelName = context.attributes.novelName {
                        Text(novelName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.orange)
                            .textCase(.uppercase)
                    }
                    Text(context.state.chapterName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    ProgressView(value: context.state.progress)
                        .progressViewStyle(.linear)
                        .tint(.orange)
                        .padding(.top, 2)
                }
                
                Spacer()
                
                Image(systemName: context.state.isPaused ? "play.circle.fill" : "pause.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.orange)
            }
            .padding()
            .activityBackgroundTint(Color(UIColor.systemBackground).opacity(0.85))
            
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded regions when user long-presses the Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "waveform")
                        .foregroundColor(.orange)
                        .font(.title2)
                        .padding(.leading, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isPaused ? "play.fill" : "pause.fill")
                        .foregroundColor(.orange)
                        .font(.title2)
                        .padding(.trailing, 8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let novelName = context.attributes.novelName {
                            Text(novelName)
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .textCase(.uppercase)
                        }
                        Text(context.state.chapterName)
                            .font(.body.weight(.semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        ProgressView(value: context.state.progress)
                            .tint(.orange)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            } compactLeading: {
                Image(systemName: "waveform")
                    .foregroundColor(.orange)
            } compactTrailing: {
                Image(systemName: context.state.isPaused ? "play.fill" : "pause.fill")
                    .foregroundColor(.orange)
            } minimal: {
                Image(systemName: "waveform")
                    .foregroundColor(.orange)
            }
        }
    }
}
#endif
