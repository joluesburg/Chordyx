//
//  SoloAccompanimentMacPanel.swift
//  Chordyx
//
//  Solo Drums host UI (Mac + iPad): enable → pick feel → play.
//  Advanced options stay available but collapsed by default.
//

#if os(macOS) || os(iOS)
import SwiftUI
import UniformTypeIdentifiers

struct SoloAccompanimentMacPanel: View {
    @Bindable var viewModel: SessionViewModel
    @Bindable var progressionStore: ProgressionStore
    @State private var isExpanded = true
    @State private var showBandOptions = false
    @State private var showAdvanced = false
    @State private var isImportingSoundFont = false
    @State private var selectedAudioUnitID: String?
    @State private var selectedAudioDevice: AudioInputDevice?

    private var detectedBPM: Int? {
        viewModel.detectedLiveBPM.map { Int($0.rounded()) }
    }

    private var hostBadgeLabel: String? {
        #if os(macOS)
        String(localized: "Mac host")
        #elseif os(iOS)
        PlatformDevice.isPad ? String(localized: "iPad host") : nil
        #else
        nil
        #endif
    }

    var body: some View {
        Group {
            if viewModel.soloAccompanimentAvailable {
                if isExpanded {
                    expandedPanel
                } else {
                    collapsedPanel
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isExpanded)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: viewModel.soloAccompanimentEnabled)
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: showBandOptions)
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: showAdvanced)
        .onAppear {
            viewModel.refreshAudioInputDevices()
            // Open Band section if bass is already part of the setup.
            if viewModel.autoBandMode.includesBass || viewModel.soloBassEnabled {
                showBandOptions = true
            }
        }
    }

    // MARK: - Collapsed / Expanded shells

    private var collapsedPanel: some View {
        Button {
            withAnimation { isExpanded = true }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: viewModel.soloAccompanimentEnabled ? "figure.wave" : "figure.wave.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(viewModel.soloAccompanimentEnabled ? AppTheme.accent : AppTheme.accentSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Solo Drums"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    tempoSubtitle
                        .font(.caption)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .glassCard()
        }
        .buttonStyle(.plain)
    }

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow

            primaryEnableToggle

            if viewModel.soloAccompanimentEnabled {
                statusSection

                if viewModel.soloDrumsAwaitingConfirmation {
                    confirmationCard
                }

                if viewModel.soloDrumsAwaitingTempoShift, let newBPM = viewModel.soloProposedTempoShiftBPM {
                    tempoShiftConfirmationCard(newBPM: Int(newBPM.rounded()))
                }

                basicsSection

                bandDisclosure

                advancedDisclosure
            } else {
                Text(String(localized: "Turn on Solo Drums, pick a feel, then play. Chordyx listens and asks before drums start."))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(14)
        .glassCard()
    }

    // MARK: - Header

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(String(localized: "Solo Drums"), systemImage: "figure.wave")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .textCase(.uppercase)
                Spacer()
                if let hostBadgeLabel {
                    Text(hostBadgeLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.background)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.accentSecondary)
                        .clipShape(Capsule())
                }
                Button {
                    withAnimation { isExpanded = false }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Collapse panel"))
            }

            Text(soloDrumsAudienceHint)
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private var soloDrumsAudienceHint: String {
        #if os(macOS)
        String(localized: "Guests on iPhone see tempo and genre when this is active.")
        #else
        String(localized: "Guests see tempo and genre when this is active.")
        #endif
    }

    // MARK: - Primary flow

    private var primaryEnableToggle: some View {
        Toggle(isOn: Binding(
            get: { viewModel.soloAccompanimentEnabled },
            set: { viewModel.setSoloAccompanimentEnabled($0) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Drums follow my playing"))
                    .font(.subheadline.weight(.semibold))
                Text(String(localized: "Play normally — Chordyx learns tempo, then asks before starting a steady drum loop."))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .toggleStyle(.switch)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            tempoRow

            if viewModel.soloDrumPhase == .listening {
                listeningRow
            } else if viewModel.soloTempoLocked {
                steadyLoopNotice
            }

            compactGenreRow
        }
    }

    // MARK: - Basics

    private var basicsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(String(localized: "Basics"))

            Toggle(isOn: Binding(
                get: { viewModel.soloAutoStyleEnabled },
                set: { viewModel.setSoloAutoStyleEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Guess the feel for me"))
                        .font(.subheadline.weight(.semibold))
                    Text(String(localized: "Picks worship, gospel, Latin, pop, and more from how you play."))
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .toggleStyle(.switch)

            if !viewModel.soloTempoLocked {
                liveGroovePresetsRow
                patternPicker
            } else {
                liveRhythmChangeSection
            }

            volumeSlider

            if viewModel.soloTempoLocked {
                Button(String(localized: "Stop & re-learn tempo")) {
                    viewModel.relearnSoloTempo()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if viewModel.soloAccompanimentEnabled {
                HStack(spacing: 8) {
                    Button(String(localized: "Preview feel (8s)")) {
                        viewModel.previewLiveGroove()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(String(localized: "I'm ready — check now")) {
                        viewModel.proposeSoloDrumDetectionNow()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(AppTheme.accent)
                    .disabled(viewModel.soloDrumPhase != .listening)
                }
            }
        }
        .padding(10)
        .background(AppTheme.accent.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Band

    private var bandDisclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            disclosureHeader(
                title: String(localized: "Add bass"),
                subtitle: String(localized: "Fill in missing players while you lead from keys."),
                isOpen: $showBandOptions
            )

            if showBandOptions {
                autoBandSection
            }
        }
    }

    private var autoBandSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "What should play along?"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)

            Picker(String(localized: "What should play along?"), selection: Binding(
                get: { viewModel.autoBandMode },
                set: { viewModel.setAutoBandMode($0) }
            )) {
                ForEach(AutoBandMode.allCases) { mode in
                    Text(friendlyAutoBandLabel(mode)).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if viewModel.autoBandMode.includesBass {
                Toggle(isOn: Binding(
                    get: { viewModel.soloBassEnabled },
                    set: { viewModel.setSoloBassEnabled($0) }
                )) {
                    Text(String(localized: "Bass follows my chords"))
                        .font(.caption.weight(.medium))
                }
                .toggleStyle(.switch)

                Picker(String(localized: "Bass feel"), selection: Binding(
                    get: { viewModel.soloBassStyle },
                    set: { viewModel.setSoloBassStyle($0) }
                )) {
                    ForEach(BassAccompanimentStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(viewModel.activeLearnedBassLine != nil)

                if viewModel.activeLearnedBassLine != nil {
                    Text(String(localized: "Using a bass line learned from your band"))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.accentSecondary)
                }

                HStack {
                    Text(String(localized: "Bass volume"))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textSecondary)
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.soloBassVolume) },
                            set: { viewModel.setSoloBassVolume(Float($0)) }
                        ),
                        in: 0.15...1.0
                    )
                    .tint(AppTheme.accentSecondary)
                }
            }

            if viewModel.activeLearnedDrumPattern != nil {
                Text(String(localized: "Using a drum pattern learned from your band"))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.accentSecondary)
            }
        }
        .padding(10)
        .background(AppTheme.accent.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func friendlyAutoBandLabel(_ mode: AutoBandMode) -> String {
        switch mode {
        case .off: String(localized: "Nothing extra")
        case .drumsOnly: String(localized: "Drums only")
        case .bassOnly: String(localized: "Bass only")
        case .fullBand: String(localized: "Drums + bass")
        }
    }

    // MARK: - Advanced

    private var advancedDisclosure: some View {
        VStack(alignment: .leading, spacing: 10) {
            disclosureHeader(
                title: String(localized: "Advanced"),
                subtitle: String(localized: "Microphone listening, drum sounds, and church library."),
                isOpen: $showAdvanced
            )

            if showAdvanced {
                VStack(alignment: .leading, spacing: 12) {
                    styleAnalysisRow
                    fusionSourceRow
                    audioAISection
                    drumSoundSourceSection
                    ServiceLearningMacSection(
                        viewModel: viewModel,
                        progressionStore: progressionStore
                    )
                }
                .padding(10)
                .background(AppTheme.surfaceElevated.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    // MARK: - Shared chrome

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(AppTheme.textSecondary)
            .textCase(.uppercase)
    }

    private func disclosureHeader(title: String, subtitle: String, isOpen: Binding<Bool>) -> some View {
        Button {
            withAnimation { isOpen.wrappedValue.toggle() }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: isOpen.wrappedValue ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.top, 4)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tempo / status

    private var tempoRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.soloTempoLocked
                     ? String(localized: "Playing at")
                     : String(localized: "Hearing"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(detectedBPM.map(String.init) ?? "—")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(viewModel.soloTempoLocked ? AppTheme.accent : AppTheme.textPrimary)
                        .contentTransition(.numericText())
                    Text("BPM")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            Spacer()

            if viewModel.soloTempoLocked, let locked = viewModel.soloLockedBPM {
                tempoLockedBadge(bpm: Int(locked.rounded()))
            } else if let detectedBPM {
                waitingBadge(detectedBPM: detectedBPM)
            } else {
                Text(String(localized: "Play a steady groove on your keyboard"))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 4)
    }

    private func tempoLockedBadge(bpm: Int) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.caption.weight(.bold))
                Text(String(localized: "Drums playing"))
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(AppTheme.accent)

            Text(viewModel.soloDrumPattern.label)
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)

            Button(String(localized: "Re-learn tempo")) {
                viewModel.relearnSoloTempo()
            }
            .buttonStyle(.borderless)
            .font(.caption2)
            .foregroundStyle(AppTheme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Drums playing at \(bpm) BPM"))
    }

    @ViewBuilder
    private func waitingBadge(detectedBPM: Int) -> some View {
        let progress = viewModel.soloDrumsJoinProgress
        VStack(alignment: .trailing, spacing: 6) {
            Text(progress >= 0.5
                 ? String(localized: "Almost ready…")
                 : String(localized: "Listening…"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
            ProgressView(value: progress)
                .frame(width: 88)
                .tint(AppTheme.accent)
            Button(String(localized: "Check now")) {
                viewModel.proposeSoloDrumDetectionNow()
            }
            .buttonStyle(.borderless)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AppTheme.accentSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Drums joining soon at \(detectedBPM) BPM"))
    }

    private var compactGenreRow: some View {
        HStack(spacing: 8) {
            Image(systemName: styleIcon)
                .foregroundStyle(hasGenreDetection ? AppTheme.accentSecondary : AppTheme.textSecondary)
            Text(hasGenreDetection
                  ? viewModel.primaryGenreDisplayLabel
                  : String(localized: "Feel will appear as you play"))
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let suggested = viewModel.suggestedDrumPattern,
               suggested != viewModel.soloDrumPattern,
               viewModel.detectedStyleConfidence >= 0.45 {
                Button(String(localized: "Use this feel")) {
                    viewModel.applySuggestedDrumPattern()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
            }
        }
        .padding(8)
        .background(AppTheme.surfaceElevated.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var confirmationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "Start drums with this feel?"), systemImage: "questionmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accent)

            if let proposal = viewModel.soloPendingProposal {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "\(Int(proposal.bpm.rounded())) BPM"))
                        .font(.title2.weight(.bold).monospacedDigit())
                    if let label = proposal.globalGenreLabel {
                        Text(label)
                            .font(.subheadline.weight(.semibold))
                        if proposal.style != .unknown {
                            Text(String(localized: "Drums: \(proposal.pattern.label)"))
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    } else if proposal.style != .unknown {
                        Text(proposal.style.label)
                            .font(.subheadline.weight(.medium))
                    }
                    Text(String(localized: "Drums loop steadily — they won't change when you switch chords."))
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            HStack(spacing: 10) {
                Button(String(localized: "Yes, start drums")) {
                    viewModel.confirmSoloDrumGroove()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)

                Button(String(localized: "Not yet — keep listening")) {
                    viewModel.rejectSoloDrumGroove()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(AppTheme.accent.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func tempoShiftConfirmationCard(newBPM: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(String(localized: "Tempo change detected"), systemImage: "speedometer")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentSecondary)

            if let locked = viewModel.soloLockedBPM {
                Text(String(localized: "Playing at \(Int(locked.rounded())) BPM — switch to \(newBPM) BPM?"))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textPrimary)
            }

            HStack(spacing: 10) {
                Button(String(localized: "Yes, adjust tempo")) {
                    viewModel.confirmSoloTempoShift()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accentSecondary)

                Button(String(localized: "Keep current tempo")) {
                    viewModel.rejectSoloTempoShift()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(AppTheme.accentSecondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var steadyLoopNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "repeat")
                    .foregroundStyle(AppTheme.accent)
                Text(String(localized: "Steady drum loop — beat stays fixed while you play chords."))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            HStack(spacing: 8) {
                Image(systemName: "metronome")
                    .foregroundStyle(AppTheme.accentSecondary)
                Text(String(localized: "Metronome stays locked to the drum grid. Pause it anytime from the tempo control."))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(10)
        .background(AppTheme.accent.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var listeningRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "ear")
                .foregroundStyle(AppTheme.accentSecondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Listening to your playing"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(String(localized: "Tap “I'm ready” when you want drums, or wait for Chordyx to ask."))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
                ProgressView(value: viewModel.soloDrumsJoinProgress)
                    .tint(AppTheme.accent)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(AppTheme.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var liveGroovePresetsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Quick feels"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)

            Text(String(localized: "Tap a feel before drums start — you can change it again while they play."))
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LiveGroovePreset.allCases) { preset in
                        Button(preset.label) {
                            viewModel.applyLiveGroovePreset(preset)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(viewModel.soloDrumPattern == preset.drumPattern ? AppTheme.accent : nil)
                    }
                }
            }
        }
    }

    private var fusionSourceRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "What Chordyx is hearing"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)
            HStack(spacing: 12) {
                sourceChip(
                    title: String(localized: "Keyboard / MIDI"),
                    value: viewModel.midiTempoConfidence,
                    isActive: viewModel.primaryTempoSource == .midi || viewModel.primaryStyleSource == .midi
                )
                sourceChip(
                    title: String(localized: "Microphone"),
                    value: viewModel.audioTempoConfidence,
                    isActive: viewModel.primaryTempoSource == .audio || viewModel.primaryStyleSource == .audio
                )
                if viewModel.primaryTempoSource == .fused || viewModel.primaryStyleSource == .fused {
                    Text(String(localized: "Combined"))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.accent.opacity(0.2))
                        .clipShape(Capsule())
                        .foregroundStyle(AppTheme.accent)
                }
            }
        }
    }

    private func sourceChip(title: String, value: Double, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isActive ? AppTheme.accent : AppTheme.textSecondary)
            ProgressView(value: value)
                .frame(width: 72)
                .tint(isActive ? AppTheme.accent : AppTheme.textSecondary)
        }
    }

    private var audioAISection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { viewModel.soloAudioAIEnabled },
                set: { viewModel.setSoloAudioAIEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Also listen with the mic"))
                        .font(.subheadline.weight(.semibold))
                    Text(String(localized: "Optional. Keyboard/MIDI is enough for most hosts. Mic turns off when drums start to avoid feedback."))
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .toggleStyle(.switch)

            if viewModel.soloAudioAIEnabled {
                if let error = viewModel.audioAILastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Picker(String(localized: "Microphone input"), selection: Binding(
                    get: { selectedAudioDevice?.id },
                    set: { newID in
                        if let newID {
                            selectedAudioDevice = viewModel.availableAudioInputDevices.first { $0.id == newID }
                        } else {
                            selectedAudioDevice = nil
                        }
                        viewModel.selectAudioInputDevice(selectedAudioDevice)
                    }
                )) {
                    Text(String(localized: "System default")).tag(Optional<UInt32>.none)
                    ForEach(viewModel.availableAudioInputDevices) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                HStack(spacing: 8) {
                    Image(systemName: viewModel.isAudioAIListening ? "mic.fill" : "mic.slash")
                        .foregroundStyle(viewModel.isAudioAIListening ? AppTheme.accent : AppTheme.textSecondary)
                    ProgressView(value: Double(min(1, viewModel.audioInputLevel * 12)))
                        .tint(AppTheme.accentSecondary)
                    Text(viewModel.isAudioAIListening ? String(localized: "Listening") : String(localized: "Idle"))
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
    }

    private var styleAnalysisRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "Detected feel"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .textCase(.uppercase)
                Spacer()
                if viewModel.isSoloStyleLearningActive {
                    Text(String(localized: "Still learning"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.accentSecondary)
                }
                let confidence = viewModel.detectedGlobalGenre != nil
                    ? viewModel.detectedGlobalGenreConfidence
                    : viewModel.detectedStyleConfidence
                if confidence >= 0.25 {
                    Text("\(Int(confidence * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            HStack(spacing: 10) {
                Image(systemName: styleIcon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(hasGenreDetection ? AppTheme.accentSecondary : AppTheme.textSecondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.primaryGenreDisplayLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    if hasGenreDetection {
                        Text(viewModel.primaryGenreDisplaySubtitle)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)
                        if !viewModel.soloTempoLocked {
                            Text(styleDetailLine)
                                .font(.caption2)
                                .foregroundStyle(AppTheme.textSecondary.opacity(0.9))
                                .lineLimit(2)
                        } else {
                            Text(String(localized: "Keeps learning — drums stay steady"))
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    } else {
                        Text(String(localized: "Play a few chord changes with rhythm"))
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }

                Spacer(minLength: 0)

                if let suggested = viewModel.suggestedDrumPattern,
                   suggested != viewModel.soloDrumPattern,
                   viewModel.detectedStyleConfidence >= 0.45 {
                    Button(viewModel.soloTempoLocked
                           ? String(localized: "Switch")
                           : String(localized: "Use")) {
                        viewModel.applySuggestedDrumPattern()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(10)
            .background(AppTheme.surfaceElevated.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if !viewModel.globalGenreAlternatives.isEmpty, viewModel.detectedGlobalGenreConfidence < 0.62 {
                genreAlternativesRow
            }
        }
    }

    private var hasGenreDetection: Bool {
        viewModel.detectedGlobalGenre != nil || viewModel.detectedLiveStyle != .unknown
    }

    private var genreAlternativesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(viewModel.globalGenreAlternatives.prefix(4)) { candidate in
                    Text(candidate.genre.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.surfaceElevated.opacity(0.55))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var styleIcon: String {
        if let region = viewModel.detectedGlobalGenre?.region,
           viewModel.detectedGlobalGenreConfidence >= 0.28 {
            return region.icon
        }
        if viewModel.detectedLiveStyle == .unknown { return "globe" }
        switch viewModel.detectedLiveStyle.category {
        case .worship:
            return viewModel.detectedLiveStyle == .gospelGroove ? "hands.clap" : "music.note"
        case .popRock:
            if viewModel.detectedLiveStyle == .edmPulse { return "waveform.path" }
            if viewModel.detectedLiveStyle == .funkGroove { return "bolt.fill" }
            return "guitars"
        case .jazzBlues: return "saxophone"
        case .latin:
            if viewModel.detectedLiveStyle == .montuno { return "pianokeys" }
            return "figure.dance"
        case .world:
            return viewModel.detectedLiveStyle == .countryTrain ? "figure.wave" : "globe.americas"
        }
    }

    private var styleDetailLine: String {
        var parts: [String] = []
        if viewModel.liveMontunoStrength >= 0.35 {
            parts.append(String(localized: "Montuno feel"))
        }
        if viewModel.detectedClaveOrientation != .unknown {
            parts.append(viewModel.detectedClaveOrientation.label)
        }
        if let pattern = viewModel.matchedRhythmPatternLabel {
            parts.append(pattern)
        }
        let sync = Int(viewModel.liveSyncopationIndex * 100)
        parts.append("\(sync)% syncopation")
        if viewModel.detectedGlobalGenre != nil, viewModel.detectedLiveStyle != .unknown {
            parts.append(String(localized: "Groove: \(viewModel.detectedLiveStyle.label)"))
        }
        return parts.joined(separator: " · ")
    }

    private var tempoSubtitle: some View {
        Group {
            if viewModel.soloAccompanimentEnabled {
                if viewModel.soloTempoLocked {
                    Text("\(detectedBPM ?? Int(viewModel.soloLockedBPM?.rounded() ?? 0)) BPM · \(viewModel.soloDrumPattern.label)")
                        .foregroundStyle(AppTheme.accent)
                } else {
                    Text(String(localized: "Listening for your tempo…"))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            } else if detectedBPM != nil {
                Text("\(detectedBPM!) BPM detected")
                    .foregroundStyle(AppTheme.textSecondary)
            } else {
                Text(String(localized: "Tap to set up"))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private var drumSoundSourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Drum sounds"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)

            Picker(String(localized: "Drum sounds"), selection: Binding(
                get: { viewModel.soloDrumSoundSourceKind },
                set: { viewModel.setSoloDrumSoundSourceKind($0) }
            )) {
                ForEach(DrumSoundSourceKind.allCases.filter { kind in
                    #if os(macOS)
                    true
                    #else
                    kind != .audioUnit
                    #endif
                }) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            Text(viewModel.soloDrumSoundSourceKind.subtitle)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

            HStack(spacing: 8) {
                if viewModel.isSoloDrumSoundSourceLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(viewModel.soloDrumSoundSourceLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
            }

            if let error = viewModel.soloDrumSoundSourceError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if viewModel.soloDrumSoundSourceKind == .userSoundFont {
                Button(String(localized: "Choose soundfont…")) {
                    isImportingSoundFont = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            #if os(macOS)
            if viewModel.soloDrumSoundSourceKind == .audioUnit {
                pluginPicker
            }
            #endif
        }
        .fileImporter(
            isPresented: $isImportingSoundFont,
            allowedContentTypes: Self.soundFontContentTypes,
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            viewModel.importSoloDrumSoundFont(from: url)
        }
    }

    #if os(macOS)
    private var pluginPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker(String(localized: "AU plugin"), selection: Binding(
                    get: { selectedAudioUnitID ?? viewModel.soloDrumAvailableAudioUnits.first?.id },
                    set: { newID in
                        selectedAudioUnitID = newID
                        let unit = viewModel.soloDrumAvailableAudioUnits.first { $0.id == newID }
                        viewModel.setSoloDrumAudioUnit(unit)
                    }
                )) {
                    ForEach(viewModel.soloDrumAvailableAudioUnits) { unit in
                        Text(unit.displayName).tag(Optional(unit.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Button(String(localized: "Refresh")) {
                    viewModel.refreshDrumAudioUnits()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            Text(String(localized: "Uses General MIDI drum notes. Latin/percussion maps vary by plugin."))
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .onAppear {
            viewModel.refreshDrumAudioUnits()
            selectedAudioUnitID = viewModel.soloDrumAvailableAudioUnits.first { $0.isLikelyDrumRelated }?.id
                ?? viewModel.soloDrumAvailableAudioUnits.first?.id
        }
    }
    #endif

    private var liveRhythmChangeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Change feel"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)

            Text(String(localized: "Swap the drum rhythm anytime — tempo and metronome stay in phase."))
                .font(.caption2)
                .foregroundStyle(AppTheme.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LiveGroovePreset.allCases) { preset in
                        Button(preset.label) {
                            viewModel.applyLiveGroovePreset(preset)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(viewModel.soloDrumPattern == preset.drumPattern ? AppTheme.accent : nil)
                    }
                }
            }

            patternPicker
        }
    }

    private var patternPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Drum feel"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .textCase(.uppercase)

            Picker(String(localized: "Drum feel"), selection: Binding(
                get: { viewModel.soloDrumPattern },
                set: { viewModel.setSoloDrumPattern($0) }
            )) {
                ForEach(DrumPattern.pickerSections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.patterns) { pattern in
                            Text(pattern.label).tag(pattern)
                        }
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            Text(viewModel.soloDrumPattern.subtitle)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private var volumeSlider: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(localized: "Drum volume"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(Int(viewModel.soloDrumVolume * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.textSecondary)
            }
            Slider(
                value: Binding(
                    get: { Double(viewModel.soloDrumVolume) },
                    set: { viewModel.setSoloDrumVolume(Float($0)) }
                ),
                in: 0.15...1.0
            )
            .tint(AppTheme.accent)
        }
    }

    private static var soundFontContentTypes: [UTType] {
        let extensions = ["sf2", "dls"]
        let types = extensions.compactMap { UTType(filenameExtension: $0) }
        return types.isEmpty ? [.data] : types
    }
}
#endif
