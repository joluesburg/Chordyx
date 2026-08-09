//
//  LiquidGlassMenus.swift
//  Chordyx
//

import SwiftUI

enum LiquidGlassMenuMetrics {
    static let cornerRadius: CGFloat = 16
}

struct LiquidGlassMenuRow: View {
    let title: String
    var icon: String?
    var isDestructive = false
    var showsCheckmark = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if let icon {
                    Label(title, systemImage: icon)
                } else {
                    Text(title)
                }
                Spacer(minLength: 24)
                if showsCheckmark {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                }
            }
            .font(.body)
            .formRowButtonLabel()
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .formRowButton()
        .disabled(disabled)
        .foregroundStyle(foregroundColor)
    }

    private var foregroundColor: Color {
        if disabled { return AppTheme.textSecondary }
        if isDestructive { return .red }
        return AppTheme.textPrimary
    }
}

struct LiquidGlassMenuSheet<Content: View>: View {
    let title: LocalizedStringKey
    @Binding var isPresented: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack {
            ScrollView {
                content()
                    .padding(.vertical, 8)
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) {
                        isPresented = false
                    }
                    .foregroundStyle(AppTheme.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
        .preferredColorScheme(.dark)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }
}

extension View {
    func liquidGlassPopoverPanel(minWidth: CGFloat = 220) -> some View {
        Group {
            if #available(iOS 26.0, macOS 26.0, *) {
                panelContent(minWidth: minWidth)
                    .glassEffect(.regular, in: .rect(cornerRadius: LiquidGlassMenuMetrics.cornerRadius, style: .continuous))
            } else {
                panelContent(minWidth: minWidth)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: LiquidGlassMenuMetrics.cornerRadius, style: .continuous))
            }
        }
        .preferredColorScheme(.dark)
    }

    private func panelContent(minWidth: CGFloat) -> some View {
        padding(.vertical, 6)
            .frame(minWidth: minWidth)
    }

    func liquidGlassPopoverChrome(clearBackground: Bool = false) -> some View {
        preferredColorScheme(.dark)
            .background(clearBackground ? Color.clear : AppTheme.background)
    }

    @ViewBuilder
    func liquidGlassMenuPresentation<MenuContent: View>(
        isPresented: Binding<Bool>,
        sheetTitle: LocalizedStringKey,
        arrowEdge: Edge = .bottom,
        minWidth: CGFloat = 220,
        maxPopoverHeight: CGFloat = 440,
        @ViewBuilder menuContent: @escaping () -> MenuContent
    ) -> some View {
        #if os(iOS)
        platformSheet(isPresented: isPresented) {
            LiquidGlassMenuSheet(title: sheetTitle, isPresented: isPresented, content: menuContent)
        }
        #else
        popover(isPresented: isPresented, arrowEdge: arrowEdge) {
            ScrollView {
                menuContent()
            }
            .frame(maxHeight: maxPopoverHeight)
            .scrollBounceBehavior(.basedOnSize)
            .liquidGlassPopoverPanel(minWidth: minWidth)
            .liquidGlassPopoverChrome()
        }
        #endif
    }
}

struct LiquidGlassPopoverMenu<Label: View, Content: View>: View {
    var arrowEdge: Edge = .bottom
    var minWidth: CGFloat = 220
    var sheetTitle: LocalizedStringKey = "Menu"
    var accessibilityLabel: LocalizedStringKey = "Menu"
    @ViewBuilder var label: () -> Label
    @ViewBuilder var content: (_ dismiss: @escaping () -> Void) -> Content

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .liquidGlassMenuPresentation(
            isPresented: $isPresented,
            sheetTitle: sheetTitle,
            arrowEdge: arrowEdge,
            minWidth: minWidth
        ) {
            content { isPresented = false }
        }
    }
}
