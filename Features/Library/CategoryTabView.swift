// CategoryTabView.swift
// Horizontal scrolling category filter pills with Liquid Glass styling.

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
                    .confirmationDialog(
                        category.name,
                        isPresented: Binding(
                            get: { actionsFor?.id == category.id },
                            set: { if !$0 { actionsFor = nil } }
                        ),
                        titleVisibility: .visible
                    ) {
                        Button("Update this category") { onUpdate(category) }
                            .disabled(isUpdating)
                        if CategoryFlags.isExcluded(category.flags) {
                            Button("Include in library updates") { onToggleUpdates(category) }
                        } else {
                            Button("Exclude from library updates") { onToggleUpdates(category) }
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                    .glassEffectID(category.id, in: namespace)
                }
              }
              .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
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
            withAnimation(AppMotion.gentle(reduceMotion: reduceMotion)) { action() }
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
        .glassEffect(.regular, in: .capsule)
        .contentShape(.capsule)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                guard let onLongPress else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                suppressTap = true
                // The lift may not report a tap at all; do not eat the next real one.
                Task { try? await Task.sleep(for: .milliseconds(600)); suppressTap = false }
                onLongPress()
            }
        )
    }
}
