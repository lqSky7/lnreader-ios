// ReaderToolbar.swift
// Glass overlay toolbar with chapter navigation and settings controls.

import SwiftUI

struct ReaderToolbar: View {
    let chapterName: String
    let hasPrevious: Bool
    let hasNext: Bool
    let isPreparingTTS: Bool
    let onDismiss: () -> Void
    let onSettings: () -> Void
    let onTTSStart: () -> Void
    let onPreviousChapter: () -> Void
    let onNextChapter: () -> Void
    let onChapterClick: () -> Void

    @Namespace private var topNamespace
    @Namespace private var bottomNamespace
    @State private var backButtonHeight: CGFloat = 44

    var body: some View {
        VStack {
            topBar
            Spacer()
            bottomBar
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        GlassEffectContainer {
            ZStack(alignment: .center) {
                // Left-aligned Back Button
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.medium))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.glass)
                    .glassEffectID("back", in: topNamespace)
                    #if os(macOS)
                        .tint(.clear)
                    #endif
                    Spacer()
                }
                .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .leading)), removal: .opacity))

                // Centered Chapter Name Pill
                Button(action: onChapterClick) {
                    Text(chapterName)
                        .lineLimit(1)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 20)
                        .frame(height: 46)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID("title", in: topNamespace)
                .padding(.horizontal, 60)
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale), removal: .opacity))

                // Right-aligned TTS Button
                HStack {
                    Spacer()
                    
                    if isPreparingTTS {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular, in: .circle)
                            .glassEffectID("tts-trigger", in: topNamespace)
                    } else {
                        Button(action: onTTSStart) {
                            Image(systemName: "waveform")
                                .font(.title2.weight(.bold))
                        }
                        .buttonStyle(.glass)
                        .glassEffectID("tts-trigger", in: topNamespace)
                        #if os(macOS)
                            .tint(.clear)
                        #endif
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        GlassEffectContainer {
            HStack {
                Button(action: onSettings) {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 46, height: 46)
                        .contentShape(Circle())
                }
                .buttonStyle(InteractivePlainButtonStyle())
                .glassEffect(.regular.interactive(), in: .circle)
                .glassEffectID("settings", in: bottomNamespace)
                
                Spacer()
                
                HStack(spacing: 0) {
                    Button(action: onPreviousChapter) {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.semibold))
                            .frame(width: 46, height: 46)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasPrevious)
                    .opacity(hasPrevious ? 1.0 : 0.4)
                    
                    Divider()
                        .frame(height: 24)
                        .background(Color.white.opacity(0.2))
                    
                    Button(action: onNextChapter) {
                        Image(systemName: "chevron.right")
                            .font(.title3.weight(.semibold))
                            .frame(width: 46, height: 46)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasNext)
                    .opacity(hasNext ? 1.0 : 0.4)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID("nav-group", in: bottomNamespace)
            }
            #if os(macOS)
                .tint(.clear)
            #endif
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

// MARK: - Interactive plain button style for unified elements

struct InteractivePlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
