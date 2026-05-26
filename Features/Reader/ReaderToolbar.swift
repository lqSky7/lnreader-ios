// ReaderToolbar.swift
// Glass overlay toolbar with chapter navigation and settings controls.

import SwiftUI

struct ReaderToolbar: View {
    let chapterName: String
    let hasPrevious: Bool
    let hasNext: Bool
    let onDismiss: () -> Void
    let onSettings: () -> Void
    let onPreviousChapter: () -> Void
    let onNextChapter: () -> Void

    @Namespace private var topNamespace
    @Namespace private var bottomNamespace

    var body: some View {
        VStack {
            topBar
            Spacer()
            bottomBar
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        ZStack {
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                }
                .buttonStyle(.glass)
                .glassEffectID("back", in: topNamespace)
                #if os(macOS)
                    .tint(.clear)
                #endif
                
                Spacer()
            }

            Text(chapterName)
                .font(Typography.caption)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .glassEffectID("title", in: topNamespace)
                .padding(.horizontal, 60)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Spacer()
            GlassEffectContainer(spacing: 16) {
                HStack(spacing: 16) {
                    Button(action: onPreviousChapter) {
                        Image(systemName: "chevron.left")
                            .font(.title3)
                    }
                    .buttonStyle(.glass)
                    .disabled(!hasPrevious)
                    .opacity(hasPrevious ? 1.0 : 0.4)
                    .glassEffectID("prev", in: bottomNamespace)

                    Button(action: onSettings) {
                        Image(systemName: "textformat.size")
                            .font(.title3)
                    }
                    .buttonStyle(.glass)
                    .glassEffectID("settings", in: bottomNamespace)

                    Button(action: onNextChapter) {
                        Image(systemName: "chevron.right")
                            .font(.title3)
                    }
                    .buttonStyle(.glass)
                    .disabled(!hasNext)
                    .opacity(hasNext ? 1.0 : 0.4)
                    .glassEffectID("next", in: bottomNamespace)
                }
            }
            #if os(macOS)
                .tint(.clear)
            #endif
            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }
}
