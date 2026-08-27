//
//  PlatformPickers.swift
//  Chordyx
//
//  Unified dropdown / picker components for consistent UX across the app.
//

import SwiftUI

// MARK: - Shared trigger styling

struct PlatformDropdownChevron: View {
    var body: some View {
        Image(systemName: "chevron.up.chevron.down")
            .font(.caption2.weight(.bold))
            .foregroundStyle(AppTheme.textSecondary.opacity(0.85))
    }
}

// MARK: - Option list sheet (Liquid Glass rows + checkmark)

struct PlatformOptionListSheet<Selection: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Selection
    @Binding var isPresented: Bool
    let options: [(Selection, String)]
    var icons: [Selection: String] = [:]
    var subtitles: [Selection: String] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(options, id: \.0) { option in
                        if let subtitle = subtitles[option.0], !subtitle.isEmpty {
                            Button {
                                selection = option.0
                                isPresented = false
                            } label: {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(option.1)
                                            .font(.body)
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.textSecondary)
                                    }
                                    Spacer(minLength: 16)
                                    if selection == option.0 {
                                        Image(systemName: "checkmark")
                                            .font(.body.weight(.semibold))
                                    }
                                }
                                .formRowButtonLabel()
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                            }
                            .formRowButton()
                            .foregroundStyle(AppTheme.textPrimary)
                        } else {
                            LiquidGlassMenuRow(
                                title: option.1,
                                icon: icons[option.0],
                                showsCheckmark: selection == option.0
                            ) {
                                selection = option.0
                                isPresented = false
                            }
                        }
                    }
                }
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
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        #endif
    }
}

// MARK: - Form dropdown → sheet list

struct PlatformFormDropdown<Selection: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Selection
    let options: [(Selection, String)]
    var icons: [Selection: String] = [:]
    var subtitles: [Selection: String] = [:]

    @State private var isPresented = false

    private var selectedLabel: String {
        options.first { $0.0 == selection }?.1 ?? "—"
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text(selectedLabel)
                    .foregroundStyle(AppTheme.textSecondary)
                PlatformDropdownChevron()
            }
            .formRowButtonLabel()
        }
        .formRowButton()
        .platformSheet(isPresented: $isPresented) {
            PlatformOptionListSheet(
                title: title,
                selection: $selection,
                isPresented: $isPresented,
                options: options,
                icons: icons,
                subtitles: subtitles
            )
        }
    }
}

// MARK: - Compact field dropdown (import review, inline rows)

struct PlatformCompactDropdown<Selection: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Selection
    let options: [(Selection, String)]

    @State private var isPresented = false

    private var selectedLabel: String {
        options.first { $0.0 == selection }?.1 ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)

            Button {
                isPresented = true
            } label: {
                HStack {
                    Text(selectedLabel)
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    PlatformDropdownChevron()
                }
                .font(.body)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(AppTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .platformSheet(isPresented: $isPresented) {
            PlatformOptionListSheet(
                title: title,
                selection: $selection,
                isPresented: $isPresented,
                options: options
            )
        }
    }
}

// MARK: - Popover option picker (toolbar chips, live session)

struct PlatformPopoverOptionPicker<Selection: Hashable, Label: View>: View {
    @Binding var selection: Selection
    let options: [(Selection, String)]
    var sheetTitle: LocalizedStringKey = "Options"
    var arrowEdge: Edge = .top
    var minWidth: CGFloat = 220
    var onChange: ((Selection) -> Void)? = nil
    @ViewBuilder var label: () -> Label

    @State private var isPresented = false

    private var selectionBinding: Binding<Selection> {
        Binding(
            get: { selection },
            set: { newValue in
                selection = newValue
                onChange?(newValue)
            }
        )
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            label()
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .platformSheet(isPresented: $isPresented) {
            PlatformOptionListSheet(
                title: sheetTitle,
                selection: selectionBinding,
                isPresented: $isPresented,
                options: options
            )
        }
        #else
        .popover(isPresented: $isPresented, arrowEdge: arrowEdge) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(options, id: \.0) { option in
                    LiquidGlassMenuRow(
                        title: option.1,
                        showsCheckmark: selection == option.0
                    ) {
                        selectionBinding.wrappedValue = option.0
                        isPresented = false
                    }
                }
            }
            .liquidGlassPopoverPanel(minWidth: minWidth)
            .liquidGlassPopoverChrome()
        }
        #endif
    }
}

// MARK: - Musical key (wheel sheet — same everywhere)

struct PlatformMusicalKeySheet: View {
    @Binding var selection: MusicalKey
    @Binding var isPresented: Bool
    var autoDetect: Binding<Bool>? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let autoDetect {
                    Toggle(isOn: autoDetect) {
                        Label(String(localized: "Auto-detect key"), systemImage: "wand.and.stars")
                            .font(.body)
                    }
                    .tint(AppTheme.accent)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    if autoDetect.wrappedValue {
                        Text(String(localized: "Learns from your chord playing and remembers when you correct the key."))
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                    }
                }

                Text(String(localized: "Select key"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)

                Picker(String(localized: "Key"), selection: $selection) {
                    ForEach(MusicalKey.allCases) { key in
                        Text(key.displayName).tag(key)
                    }
                }
                #if os(iOS)
                .pickerStyle(.wheel)
                #else
                .pickerStyle(.menu)
                #endif
                .labelsHidden()
                .frame(maxHeight: 200)
            }
            .navigationTitle(String(localized: "Key"))
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
        .presentationDetents([.height(autoDetect == nil ? 300 : 380)])
        .presentationDragIndicator(.visible)
        #endif
    }
}

struct PlatformMusicalKeyField: View {
    enum Style {
        case form
        case compact
    }

    let title: LocalizedStringKey
    @Binding var selection: MusicalKey
    var style: Style = .form

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            switch style {
            case .form:
                HStack {
                    Text(title)
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    Text(selection.displayName)
                        .foregroundStyle(AppTheme.textSecondary)
                    PlatformDropdownChevron()
                }
                .formRowButtonLabel()
            case .compact:
                HStack {
                    Text(selection.displayName)
                        .foregroundStyle(AppTheme.textPrimary)
                    Spacer()
                    PlatformDropdownChevron()
                }
                .font(.body)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(AppTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .modifier(MusicalKeyFieldButtonStyle(style: style))
        .platformSheet(isPresented: $isPresented) {
            PlatformMusicalKeySheet(
                selection: $selection,
                isPresented: $isPresented
            )
        }
    }
}

private struct MusicalKeyFieldButtonStyle: ViewModifier {
    let style: PlatformMusicalKeyField.Style

    func body(content: Content) -> some View {
        switch style {
        case .form:
            content.formRowButton()
        case .compact:
            content.buttonStyle(.plain)
        }
    }
}

// MARK: - Session host key picker (transpose + auto-detect)

enum SessionKeySelectionMode: String, CaseIterable, Identifiable {
    case auto
    case manual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: String(localized: "Auto (AI)")
        case .manual: String(localized: "Manual")
        }
    }
}

/// Key mode + manual picker for New Session (host setup) — Auto (AI) or Manual.
struct HostSetupMusicalKeyCard: View {
    @Binding var mode: SessionKeySelectionMode
    @Binding var manualKey: MusicalKey
    var showsSpellingHint: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(String(localized: "Key mode"), selection: $mode) {
                ForEach(SessionKeySelectionMode.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if mode == .auto {
                autoKeySetupPanel
            } else {
                PlatformMusicalKeyField(title: "Key", selection: $manualKey, style: .compact)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .background(AppTheme.surfaceElevated.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    }
            }

            if showsSpellingHint {
                Text(String(localized: "Spells chord names with sharps or flats."))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private var autoKeySetupPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.title3)
                    .foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Auto-detect key"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(String(localized: "Live AI listens to the mic and your chords in real time, and updates when the key changes."))
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surfaceElevated.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }

            Text(String(localized: "No fixed lock in Auto — play chords and Live AI keeps following. Use Manual only to freeze a key."))
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SessionMusicalKeyPicker: View {
    @ObservedObject var viewModel: SessionViewModel
    @Binding var isPresented: Bool

    @State private var mode: SessionKeySelectionMode = .auto

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker(String(localized: "Key mode"), selection: $mode) {
                    ForEach(SessionKeySelectionMode.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .onChange(of: mode) { _, newMode in
                    viewModel.setAutoDetectKey(newMode == .auto)
                }

                if mode == .auto {
                    autoKeyPanel
                } else {
                    manualKeyPanel
                }

                Spacer(minLength: 0)
            }
            .navigationTitle(String(localized: "Key"))
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
            .onAppear {
                mode = viewModel.payload.autoDetectKey ? .auto : .manual
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
        .preferredColorScheme(.dark)
        #if os(iOS)
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
        #endif
    }

    private var autoKeyPanel: some View {
        VStack(spacing: 14) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 28))
                .foregroundStyle(AppTheme.accent)

            if viewModel.payload.isKeyAutoDetected {
                Text(viewModel.displayNotation(isGuest: false).cycleGlyph(for: viewModel.payload.key))
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                if let scaleCaption = viewModel.autoKeyScaleCaption(isGuest: false) {
                    Text(scaleCaption)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.accentSecondary)
                        .multilineTextAlignment(.center)
                }

                if let scale = viewModel.payload.detectedScale {
                    Text(scalePitchClassLine(
                        key: viewModel.payload.key,
                        scale: scale
                    ))
                    .font(.caption.monospaced())
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                }

                Label(String(localized: "Following live — key, scale & modes"), systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.accentSecondary)

                Button {
                    viewModel.releaseAutoKeyFollow()
                } label: {
                    Label(String(localized: "Re-listen"), systemImage: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: 220)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.accent)
            } else {
                Text(String(localized: "Listening for key & scale…"))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)

                Label(String(localized: "Listening to the room and your chords…"), systemImage: "waveform")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Text(String(localized: "Live AI detects tonic + scale/mode (major, minor, Dorian, Mixolydian, pentatonic, blues…). Mic leads; chords confirm. Use Re-listen if it sticks."))
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text(String(localized: "To freeze a key yourself, choose Manual above."))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func scalePitchClassLine(
        key: MusicalKey,
        scale: MusicalScaleQuality
    ) -> String {
        let names = key.prefersFlats ? Transposer.flatNames : Transposer.sharpNames
        let degrees = scale.intervals.map { interval in
            names[(key.pitchClass + interval) % 12]
        }
        return degrees.joined(separator: " · ")
    }

    private var manualKeyPanel: some View {
        VStack(spacing: 12) {
            Text(String(localized: "Chart key — auto-detection is off"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

            Picker(String(localized: "Key"), selection: Binding(
                get: { viewModel.payload.key },
                set: { viewModel.transpose(to: $0) }
            )) {
                ForEach(MusicalKey.allCases) { key in
                    Text(key.displayName).tag(key)
                }
            }
            #if os(iOS)
            .pickerStyle(.wheel)
            #else
            .pickerStyle(.menu)
            #endif
            .labelsHidden()
            .frame(maxHeight: 200)
        }
    }
}

// MARK: - Worship section kind picker

struct PlatformWorshipSectionPicker<Label: View>: View {
    var arrowEdge: Edge = .bottom
    let onSelect: (WorshipSectionKind) -> Void
    @ViewBuilder var label: () -> Label

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .liquidGlassMenuPresentation(
            isPresented: $isPresented,
            sheetTitle: "Add Section",
            arrowEdge: arrowEdge,
            minWidth: 220
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(WorshipSectionKind.allCases) { kind in
                    LiquidGlassMenuRow(
                        title: kind.defaultName,
                        icon: kind.icon
                    ) {
                        onSelect(kind)
                        isPresented = false
                    }
                }
            }
        }
    }
}
