//
//  PlatformModifiers.swift
//  Chordyx
//

import SwiftUI

// MARK: - Home destination shell (iPad / Mac fullscreen)

struct PlatformHomeDestinationShell<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.bold))
                        Text(String(localized: "Back"))
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.backgroundGradient.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

private struct PlatformHomeCoverModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    var onDismiss: (() -> Void)?
    @ViewBuilder var sheetContent: () -> SheetContent
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var usesFullscreenPresentation: Bool {
        #if os(macOS)
        true
        #else
        horizontalSizeClass == .regular
        #endif
    }

    func body(content: Content) -> some View {
        #if os(macOS)
        if let onDismiss {
            content.sheet(isPresented: $isPresented, onDismiss: onDismiss) {
                PlatformHomeDestinationShell(content: sheetContent)
            }
        } else {
            content.sheet(isPresented: $isPresented) {
                PlatformHomeDestinationShell(content: sheetContent)
            }
        }
        #else
        Group {
            if usesFullscreenPresentation {
                content.fullScreenCover(isPresented: $isPresented, onDismiss: onDismiss) {
                    PlatformHomeDestinationShell(content: sheetContent)
                }
            } else if let onDismiss {
                content.sheet(isPresented: $isPresented, onDismiss: onDismiss) {
                    sheetContent()
                }
            } else {
                content.sheet(isPresented: $isPresented) {
                    sheetContent()
                }
            }
        }
        #endif
    }
}

extension View {
    /// iPhone: sheet. iPad + Mac: fullscreen with a top Back control.
    @ViewBuilder
    func platformHomeCover<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(
            PlatformHomeCoverModifier(
                isPresented: isPresented,
                onDismiss: onDismiss,
                sheetContent: content
            )
        )
    }

    @ViewBuilder
    func platformInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformNavigationBarHidden(_ hidden: Bool = true) -> some View {
        #if os(iOS)
        navigationBarHidden(hidden)
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformToolbarBackground(_ color: Color) -> some View {
        #if os(iOS)
        toolbarBackground(color, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        #else
        self
        #endif
    }

    @ViewBuilder
    func platformFullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(iOS)
        if let onDismiss {
            fullScreenCover(isPresented: isPresented, onDismiss: onDismiss, content: content)
        } else {
            fullScreenCover(isPresented: isPresented, content: content)
        }
        #else
        if let onDismiss {
            sheet(isPresented: isPresented, onDismiss: onDismiss) {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.backgroundGradient.ignoresSafeArea())
            }
        } else {
            sheet(isPresented: isPresented) {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.backgroundGradient.ignoresSafeArea())
            }
        }
        #endif
    }

    /// Session canvas fills the screen on Mac; iPhone/iPad use native fullScreenCover.
    @ViewBuilder
    func platformSessionSheetFrame() -> some View {
        #if os(macOS)
        frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        self
        #endif
    }

    /// iPhone: resizable sheet over the session. iPad + Mac: fullscreen for the full 88-key keyboard.
    @ViewBuilder
    func platformPianoSheet<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(
            PlatformPianoSheetModifier(
                isPresented: isPresented,
                onDismiss: onDismiss,
                sheetContent: content
            )
        )
    }
}

private struct PlatformPianoSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    var onDismiss: (() -> Void)?
    @ViewBuilder var sheetContent: () -> SheetContent
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var usesFullscreenPresentation: Bool {
        #if os(macOS)
        true
        #else
        horizontalSizeClass == .regular
        #endif
    }

    func body(content: Content) -> some View {
        #if os(macOS)
        if let onDismiss {
            content.sheet(isPresented: $isPresented, onDismiss: onDismiss) {
                sheetContent()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.backgroundGradient.ignoresSafeArea())
            }
        } else {
            content.sheet(isPresented: $isPresented) {
                sheetContent()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.backgroundGradient.ignoresSafeArea())
            }
        }
        #else
        Group {
            if usesFullscreenPresentation {
                content.fullScreenCover(isPresented: $isPresented, onDismiss: onDismiss) {
                    sheetContent()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppTheme.backgroundGradient.ignoresSafeArea())
                }
            } else if let onDismiss {
                content.sheet(isPresented: $isPresented, onDismiss: onDismiss) {
                    sheetContent()
                        .presentationDetents([.fraction(0.42), .large])
                        .presentationDragIndicator(.visible)
                        .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.42)))
                }
            } else {
                content.sheet(isPresented: $isPresented) {
                    sheetContent()
                        .presentationDetents([.fraction(0.42), .large])
                        .presentationDragIndicator(.visible)
                        .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.42)))
                }
            }
        }
        #endif
    }
}

struct PlatformEditButton: View {
    var body: some View {
        #if os(iOS)
        EditButton()
        #else
        EmptyView()
        #endif
    }
}

extension View {
    @ViewBuilder
    func platformWheelPickerStyle(height: CGFloat = 120) -> some View {
        #if os(iOS)
        pickerStyle(.wheel)
            .frame(height: height)
        #else
        pickerStyle(.menu)
        #endif
    }

    /// Library flows use the full window on Mac/iPad when presented from home.
    @ViewBuilder
    func platformLibrarySheetFrame() -> some View {
        modifier(PlatformLibrarySheetFrameModifier())
    }

    /// Wider readable width for home-style menus on iPad and Mac.
    @ViewBuilder
    func platformHomeContentWidth() -> some View {
        modifier(PlatformHomeContentWidthModifier())
    }
}

private struct PlatformLibrarySheetFrameModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .frame(minWidth: 540, idealWidth: 680, maxWidth: 820, minHeight: 520)
        #elseif os(iOS)
        if horizontalSizeClass == .regular {
            content
                .frame(minWidth: 480, idealWidth: 620, maxWidth: 760, minHeight: 520)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

private struct PlatformHomeContentWidthModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: PlatformLayout.homeContentMaxWidth(horizontalSizeClass: horizontalSizeClass))
            .frame(maxWidth: .infinity)
    }
}

enum PlatformLayout {
    static func homeContentMaxWidth(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        #if os(macOS)
        1180
        #else
        horizontalSizeClass == .regular ? 920 : .infinity
        #endif
    }

    static func homeHorizontalPadding(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        #if os(macOS)
        48
        #else
        horizontalSizeClass == .regular ? 48 : 24
        #endif
    }

    static func usesWideHomeLayout(horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        usesWideSessionLayout(horizontalSizeClass: horizontalSizeClass)
    }

    static func usesWideSessionLayout(horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        #if os(macOS)
        true
        #else
        horizontalSizeClass == .regular
        #endif
    }

    static func sessionPanelMaxWidth(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        #if os(macOS)
        1020
        #else
        horizontalSizeClass == .regular ? 860 : .infinity
        #endif
    }

    static func sessionHorizontalPadding(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        #if os(macOS)
        40
        #else
        horizontalSizeClass == .regular ? 40 : 20
        #endif
    }
}
