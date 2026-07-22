//
//  PlatformModifiers.swift
//  Chordyx
//

import SwiftUI

// MARK: - Home destination shell (iPad / Mac fullscreen)

private struct UsesHomeDestinationShellKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True when a flow is embedded in `PlatformHomeDestinationShell` (iPad/Mac fullscreen).
    var usesHomeDestinationShell: Bool {
        get { self[UsesHomeDestinationShellKey.self] }
        set { self[UsesHomeDestinationShellKey.self] = newValue }
    }
}

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
                .environment(\.usesHomeDestinationShell, true)
                .platformDesktopControls()
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
                    .platformLibrarySheetFrame()
                    .presentationSizing(.page)
            }
        } else {
            content.sheet(isPresented: $isPresented) {
                PlatformHomeDestinationShell(content: sheetContent)
                    .platformLibrarySheetFrame()
                    .presentationSizing(.page)
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

    /// Setup sheets (New Session, Join, etc.) — large title keeps Cancel/Start readable.
    @ViewBuilder
    func platformSetupSheetNavigation() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.large)
        #else
        self
        #endif
    }

    /// Hides the system navigation bar when using `PlatformSetupSheetHeader`.
    @ViewBuilder
    func platformSetupSheetToolbarHidden(_ hidden: Bool) -> some View {
        #if os(iOS)
        if hidden {
            toolbar(.hidden, for: .navigationBar)
        } else {
            self
        }
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
            fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) {
                content()
                    .platformDesktopControls()
            }
        } else {
            fullScreenCover(isPresented: isPresented) {
                content()
                    .platformDesktopControls()
            }
        }
        #else
        if let onDismiss {
            sheet(isPresented: isPresented, onDismiss: onDismiss) {
                content()
                    .platformSessionSheetFrame()
                    .background(AppTheme.backgroundGradient.ignoresSafeArea())
                    .platformDesktopControls()
            }
        } else {
            sheet(isPresented: isPresented) {
                content()
                    .platformSessionSheetFrame()
                    .background(AppTheme.backgroundGradient.ignoresSafeArea())
                    .platformDesktopControls()
            }
        }
        #endif
    }

    /// Session canvas fills the screen on Mac; iPhone/iPad use native fullScreenCover.
    @ViewBuilder
    func platformSessionSheetFrame() -> some View {
        #if os(macOS)
        frame(
            minWidth: 900,
            idealWidth: 1100,
            maxWidth: .infinity,
            minHeight: 640,
            idealHeight: 760,
            maxHeight: .infinity
        )
        .presentationSizing(.page)
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
    @State private var phonePianoDetent: PresentationDetent = .fraction(0.72)

    private var usesFullscreenPresentation: Bool {
        #if os(macOS)
        true
        #elseif os(iOS)
        !PlatformDevice.isPhone
        #else
        false
        #endif
    }

    func body(content: Content) -> some View {
        #if os(macOS)
        if let onDismiss {
            content.sheet(isPresented: $isPresented, onDismiss: onDismiss) {
                macPianoSheetBody
            }
        } else {
            content.sheet(isPresented: $isPresented) {
                macPianoSheetBody
            }
        }
        #else
        Group {
            if usesFullscreenPresentation {
                content.fullScreenCover(isPresented: $isPresented, onDismiss: onDismiss) {
                    sheetContent()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppTheme.backgroundGradient.ignoresSafeArea())
                        .platformDesktopControls()
                }
            } else if let onDismiss {
                content.sheet(isPresented: $isPresented, onDismiss: onDismiss) {
                    sheetContent()
                        // Tall default so dual-row keys stay playable; user can still expand to large.
                        .presentationDetents([.fraction(0.72), .large], selection: $phonePianoDetent)
                        .presentationDragIndicator(.visible)
                        .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.72)))
                        .platformDesktopControls()
                }
            } else {
                content.sheet(isPresented: $isPresented) {
                    sheetContent()
                        .presentationDetents([.fraction(0.72), .large], selection: $phonePianoDetent)
                        .presentationDragIndicator(.visible)
                        .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.72)))
                        .platformDesktopControls()
                }
            }
        }
        #endif
    }

    #if os(macOS)
    /// Prefer a wide sheet so all 88 keys can fit in one row; grows taller if dual-row is needed.
    private var macPianoSheetBody: some View {
        sheetContent()
            .frame(minWidth: 1400, idealWidth: .infinity, maxWidth: .infinity,
                   minHeight: 520, idealHeight: 640, maxHeight: 760)
            .background(AppTheme.backgroundGradient.ignoresSafeArea())
            .platformDesktopControls()
    }
    #endif
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

// MARK: - Desktop segmented control (Now / Ring / etc.)

struct PlatformSegmentedOption<Selection: Hashable> {
    let value: Selection
    let label: LocalizedStringKey
}

struct PlatformSegmentedPicker<Selection: Hashable>: View {
    private let title: LocalizedStringKey
    @Binding private var selection: Selection
    private let options: [PlatformSegmentedOption<Selection>]

    init(
        _ title: LocalizedStringKey,
        selection: Binding<Selection>,
        options: [(Selection, LocalizedStringKey)]
    ) {
        self.title = title
        self._selection = selection
        self.options = options.map { PlatformSegmentedOption(value: $0.0, label: $0.1) }
    }

    init(
        _ title: LocalizedStringKey,
        selection: Binding<Selection>,
        stringOptions: [(Selection, String)]
    ) {
        self.init(
            title,
            selection: selection,
            options: stringOptions.map { ($0.0, LocalizedStringKey(stringLiteral: $0.1)) }
        )
    }

    var body: some View {
        // Button segments work reliably inside Form on iPhone, iPad, and Mac.
        // Native .segmented pickers often ignore taps in Form (TestFlight / iOS 18).
        desktopBody
    }

    private var desktopBody: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.value) { option in
                let isSelected = selection == option.value
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)
                        .background(
                            isSelected ? AppTheme.accent.opacity(0.22) : AppTheme.surface,
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .stroke(
                                    isSelected ? AppTheme.accent.opacity(0.45) : Color.white.opacity(0.08),
                                    lineWidth: 1
                                )
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }
}

private struct PlatformDesktopControlsModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(PlatformResponsivePlainButtonStyle())
    }
}

private struct PlatformResponsivePlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Custom top bar for setup sheets — avoids toolbar truncation from global button styles.
struct PlatformSetupSheetHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    var cancelTitle: String
    let onCancel: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: LocalizedStringKey,
        cancelTitle: String = String(localized: "Cancel"),
        onCancel: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.cancelTitle = cancelTitle
        self.onCancel = onCancel
        self.trailing = trailing
    }

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 88)

            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text(cancelTitle)
                        .font(.body)
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)

                Spacer(minLength: 0)

                trailing()
                    .layoutPriority(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(AppTheme.background)
    }
}

extension PlatformSetupSheetHeader where Trailing == PlatformSetupSheetHeaderSpacer {
    init(
        title: LocalizedStringKey,
        cancelTitle: String = String(localized: "Cancel"),
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.cancelTitle = cancelTitle
        self.onCancel = onCancel
        self.trailing = { PlatformSetupSheetHeaderSpacer() }
    }
}

struct PlatformSetupSheetHeaderSpacer: View {
    var body: some View {
        Color.clear
            .frame(width: 56, height: 1)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Makes custom-styled buttons respond to taps across the full label area.
    func platformDesktopControls() -> some View {
        modifier(PlatformDesktopControlsModifier())
    }

    /// Expands a custom `Button` label so an entire Form/list row is tappable.
    func formRowButtonLabel(alignment: Alignment = .leading) -> some View {
        frame(maxWidth: .infinity, alignment: alignment)
            .contentShape(Rectangle())
    }

    /// Apply to the `Button` (not only its label) so taps register across the full list row.
    func formRowButton(alignment: Alignment = .leading) -> some View {
        frame(maxWidth: .infinity, alignment: alignment)
            .contentShape(Rectangle())
            .platformDesktopControls()
    }

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

    /// Pre-service checklist sheet sizing — Mac needs explicit dimensions for toolbar actions.
    @ViewBuilder
    func platformPreServiceSheetFrame() -> some View {
        #if os(macOS)
        frame(minWidth: 460, idealWidth: 520, maxWidth: 580, minHeight: 520, idealHeight: 600)
        #else
        self
        #endif
    }

    /// Standard chrome for sheets on Mac (nested pickers, settings, lists).
    @ViewBuilder
    func platformSheetChrome(large: Bool = false) -> some View {
        #if os(macOS)
        if large {
            self.platformLibrarySheetFrame()
                .presentationSizing(.page)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.backgroundGradient.ignoresSafeArea())
                .preferredColorScheme(.dark)
        } else {
            frame(
                minWidth: 440,
                idealWidth: 520,
                maxWidth: 680,
                minHeight: 380,
                idealHeight: 480,
                maxHeight: .infinity
            )
            .presentationSizing(.form)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.backgroundGradient.ignoresSafeArea())
            .preferredColorScheme(.dark)
        }
        #else
        self
        #endif
    }

    /// iPhone: native sheet. Mac: sized sheet so lists and pickers are readable (including nested sheets).
    @ViewBuilder
    func platformSheet<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        large: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(
            PlatformSheetModifier(
                isPresented: isPresented,
                onDismiss: onDismiss,
                large: large,
                sheetContent: content
            )
        )
    }
}

private struct PlatformSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    var onDismiss: (() -> Void)?
    var large: Bool
    @ViewBuilder var sheetContent: () -> SheetContent

    func body(content: Content) -> some View {
        if let onDismiss {
            content.sheet(isPresented: $isPresented, onDismiss: onDismiss) {
                sheetContent()
                    .platformSheetChrome(large: large)
            }
        } else {
            content.sheet(isPresented: $isPresented) {
                sheetContent()
                    .platformSheetChrome(large: large)
            }
        }
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

    /// Large screens prefer a wide piano presentation; AdaptivePianoBoard still picks fitted vs dual-row by width.
    static func usesFullPianoKeyboard(horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        #if os(macOS)
        true
        #elseif os(iOS)
        !PlatformDevice.isPhone
        #else
        false
        #endif
    }
}
