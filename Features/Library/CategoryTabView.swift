// CategoryTabView.swift
// Horizontal scrolling category filter pills with Liquid Glass styling.

import SwiftUI

struct CategoryTabView: View {
    let categories: [Category]
    @Binding var selectedCategory: Category?
    @Namespace private var namespace

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
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
            withAnimation { action() }
        } label: {
            Text(title)
                .font(Typography.caption)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .glassEffect(
            isSelected ? .regular.tint(AppTheme.accent) : .regular,
            in: .capsule
        )
        .contentShape(.capsule)
    }
}
