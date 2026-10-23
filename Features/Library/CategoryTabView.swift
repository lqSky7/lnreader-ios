// CategoryTabView.swift
// Horizontal scrolling category filter pills with Liquid Glass styling.

import SwiftUI

struct CategoryTabView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let categories: [Category]
    @Binding var selectedCategory: Category?
    @Namespace private var namespace

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
                        isSelected: selectedCategory?.id == category.id
                    ) {
                        selectedCategory = category
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
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(AppMotion.gentle(reduceMotion: reduceMotion)) { action() }
        } label: {
            Text(title)
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
    }
}
