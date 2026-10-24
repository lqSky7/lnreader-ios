// CategoryTabView.swift
// Horizontal scrolling category filter pills with Liquid Glass styling.

import SwiftData
import SwiftUI

struct CategoryTabView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let categories: [Category]
    @Binding var selectedCategory: Category?
    var isUpdating = false
    var onUpdate: (Category) -> Void = { _ in }
    var onToggleUpdates: (Category) -> Void = { _ in }
    @Namespace private var namespace
    /// Category whose actions are showing, opened by a long press.
    @State private var actionsFor: Category?
    /// A long press ends with a lift that would also count as a tap.
    @State private var suppressTap = false
    /// Chip sizes, so the popover can anchor to a rect slightly larger than its chip.
    @State private var chipSizes: [PersistentIdentifier: CGSize] = [:]
    /// Gap between a chip and its actions popover.
    private let popoverGap: CGFloat = 10

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
              // Without a stack the container lays its pills out vertically.
              HStack(spacing: 8) {
                categoryPill(
                    title: "All",
                    isSelected: selectedCategory == nil
                ) {
                    selectedCategory = nil
                }
                .glassEffectID("all", in: namespace)

                ForEach(categories) { category in
                    categoryPill(
                        title: category.name,
                        isSelected: selectedCategory?.id == category.id,
                        isExcluded: CategoryFlags.isExcluded(category.flags),
                        onLongPress: { actionsFor = category }
                    ) {
                        selectedCategory = category
                    }
                    // On the chip itself: a popover anchors to the view that owns it.
                    // The anchor rect is the chip grown by `popoverGap`, which is
                    // how a popover is pushed away from its source.
                    .onGeometryChange(for: CGSize.self, of: \.size) { chipSizes[category.id] = $0 }
                    .popover(
                        isPresented: Binding(
                            get: { actionsFor?.id == category.id },
                            set: { if !$0 { actionsFor = nil } }
                        ),
                        attachmentAnchor: .rect(.rect(anchorRect(for: category))),
                        arrowEdge: .top
                    ) {
                        actionsPopover(for: category)
                    }
                    .glassEffectID(category.id, in: namespace)
                }
              }
              .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }

    private func anchorRect(for category: Category) -> CGRect {
        let size = chipSizes[category.id] ?? .zero
        return CGRect(x: -popoverGap, y: -popoverGap,
                      width: size.width + popoverGap * 2, height: size.height + popoverGap * 2)
    }

    private func actionsPopover(for category: Category) -> some View {
        let excluded = CategoryFlags.isExcluded(category.flags)
        return VStack(alignment: .leading, spacing: 0) {
            Text(category.name)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            Divider()
            popoverAction("Update this category", systemImage: "arrow.clockwise", disabled: isUpdating) {
                onUpdate(category)
            }
            Divider()
            popoverAction(
                excluded ? "Include in library updates" : "Exclude from library updates",
                systemImage: excluded ? "arrow.triangle.2.circlepath" : "pause.circle"
            ) {
                onToggleUpdates(category)
            }
        }
        .frame(minWidth: 250)
        .presentationCompactAdaptation(.popover)
    }

    private func popoverAction(
        _ title: String, systemImage: String, disabled: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button {
            actionsFor = nil
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    @ViewBuilder
    private func categoryPill(
        title: String,
        isSelected: Bool,
        isExcluded: Bool = false,
        onLongPress: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            if suppressTap {
                suppressTap = false
                return
            }
            withAnimation(AppMotion.tabSwitch(reduceMotion: reduceMotion)) { action() }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                if isExcluded {
                    Image(systemName: "pause.circle")
                        .accessibilityLabel("Excluded from updates")
                }
            }
                .font(Typography.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        // A tinted glass pill reads as selected in any colour scheme; weight and
        // colour alone were too subtle against the other pills.
        .glassEffect(
            isSelected ? .regular.tint(Color.primary.opacity(0.28)).interactive() : .regular.interactive(),
            in: .capsule)
        .contentShape(.capsule)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                guard let onLongPress else { return }
                Haptics.shared.impact(.medium)
                suppressTap = true
                // The lift may not report a tap at all; do not eat the next real one.
                Task { try? await Task.sleep(for: .milliseconds(600)); suppressTap = false }
                onLongPress()
            }
        )
    }
}
