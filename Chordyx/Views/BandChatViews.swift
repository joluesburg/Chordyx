//
//  BandChatViews.swift
//  Chordyx
//
//  Shared band chat — opt-in sheet, safe for typing on Mac.
//

import SwiftUI

/// Compact entry point — badge only, no live-stage banners.
struct BandChatEntryButton: View {
    var unreadCount: Int
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.surfaceElevated.opacity(0.92))
                    .clipShape(Circle())

                if unreadCount > 0 {
                    Text(unreadCount > 9 ? "9+" : "\(unreadCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.background)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(AppTheme.textPrimary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(AppTheme.accent, lineWidth: 1.5)
                        )
                        .offset(x: 6, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Band chat"))
        .accessibilityHint(String(localized: "Open shared chat with host and guests"))
        .accessibilityValue(
            unreadCount > 0
                ? String(format: String(localized: "%lld unread"), unreadCount)
                : String(localized: "No unread messages")
        )
    }
}

/// Opt-in sheet chat for everyone in the session.
struct BandChatSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: SessionViewModel
    /// Used when presented as an overlay panel (sheet `dismiss` is a no-op there).
    var onClose: (() -> Void)? = nil
    @State private var draft = ""
    @State private var showChatSettings = false
    @FocusState private var isComposerFocused: Bool

    private var messages: [SessionQuickMessage] {
        viewModel.displayedBandChatMessages
    }

    private var confirmedIDs: Set<UUID> {
        Set(viewModel.payload.bandChatMessages.map(\.id))
    }

    private var myName: String {
        SessionManager.currentDisplayName()
    }

    private var peerCountLabel: String {
        let peers = viewModel.sessionManager.connectedPeers.count
        if viewModel.role == .host {
            if peers == 0 {
                return String(localized: "Only you right now")
            }
            return String(format: String(localized: "%lld connected"), peers)
        }
        if viewModel.isRemoteLinkActive {
            return String(localized: "Connected via Internet")
        }
        if peers > 0 {
            return String(localized: "Connected to host")
        }
        return String(localized: "Waiting for connection…")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusBar

                messageList
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider().opacity(0.35)

                presetRow
                composerRow
            }
            .background(AppTheme.background)
            .navigationTitle(String(localized: "Band chat"))
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Close")) { closeChat() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showChatSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(String(localized: "Chat settings"))
                }
            }
            .platformSheet(isPresented: $showChatSettings) {
                BandChatSettingsView()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.isBandChatPresented = true
            viewModel.bandChatToastText = nil
            #if os(macOS)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                isComposerFocused = true
            }
            #else
            isComposerFocused = true
            #endif
        }
        .onDisappear {
            viewModel.isBandChatPresented = false
        }
    }

    private func closeChat() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.3.fill")
                .font(.caption2)
                .foregroundStyle(AppTheme.accentSecondary)
            Text(peerCountLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
            Spacer(minLength: 0)
            if let status = viewModel.bandChatStatusMessage {
                Text(status)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppTheme.surface.opacity(0.55))
    }

    @ViewBuilder
    private var messageList: some View {
        if messages.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                Text(String(localized: "Message the whole band"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(String(localized: "Quick chips or type below. Stays off the live stage until you open it."))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(messages.reversed()) { message in
                            bandChatBubble(
                                message,
                                isPending: !confirmedIDs.contains(message.id)
                                    && message.senderName == myName
                            )
                            .id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onAppear { scrollToLatest(proxy) }
                .onChange(of: messages.first?.id) { _, _ in
                    scrollToLatest(proxy, animated: true)
                }
            }
        }
    }

    private var presetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SessionQuickMessage.chatPresets, id: \.0) { text, symbol in
                    Button {
                        _ = viewModel.sendBandChat(text, symbol: symbol)
                    } label: {
                        Label(text, systemImage: symbol)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(AppTheme.surfaceElevated)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.textPrimary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }

    private var composerRow: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(String(localized: "Message the band"), text: $draft)
                    #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.send)
                    #endif
                    .focused($isComposerFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onSubmit(sendDraft)

                Button(action: sendDraft) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSendDraft ? AppTheme.accent : AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSendDraft)
                .accessibilityLabel(String(localized: "Send"))
            }

            if draft.count > BandChatLimits.maxTextLength - 40 {
                Text("\(min(draft.count, BandChatLimits.maxTextLength))/\(BandChatLimits.maxTextLength)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var canSendDraft: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendDraft() {
        let text = draft
        guard viewModel.sendBandChat(text) else {
            isComposerFocused = true
            return
        }
        draft = ""
        isComposerFocused = true
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy, animated: Bool = false) {
        guard let last = messages.first?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(last, anchor: .bottom)
        }
    }

    @ViewBuilder
    private func bandChatBubble(_ message: SessionQuickMessage, isPending: Bool) -> some View {
        let isMine = message.senderName == myName
        HStack {
            if isMine { Spacer(minLength: 40) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(isMine ? String(localized: "You") : message.senderName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                    Text(Self.relativeTime(message.sentAt))
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.8))
                    if isPending {
                        Text(String(localized: "Sending…"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.accentSecondary)
                    }
                }
                HStack(alignment: .top, spacing: 6) {
                    if !isMine {
                        Image(systemName: message.symbol)
                            .font(.caption)
                            .foregroundStyle(AppTheme.accentSecondary)
                    }
                    Text(message.text)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(isMine ? .trailing : .leading)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isMine ? AppTheme.accent.opacity(0.22) : AppTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .opacity(isPending ? 0.7 : 1)
            if !isMine { Spacer(minLength: 40) }
        }
    }

    private static func relativeTime(_ sentAt: Double) -> String {
        let elapsed = max(0, Date().timeIntervalSince1970 - sentAt)
        if elapsed < 45 { return String(localized: "now") }
        if elapsed < 3600 {
            return String(format: String(localized: "%lldm"), Int(elapsed / 60))
        }
        return String(format: String(localized: "%lldh"), Int(elapsed / 3600))
    }
}

/// Local device preferences for band chat alerts (does not change what others see).
struct BandChatSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(GuestDisplaySettings.bandChatBadgesKey) private var badgesEnabled = true
    @AppStorage(GuestDisplaySettings.bandChatHapticsKey) private var hapticsEnabled = true
    @AppStorage(GuestDisplaySettings.bandChatSoundsKey) private var soundsEnabled = false
    @AppStorage(GuestDisplaySettings.bandChatQuietDuringLiveKey) private var quietDuringLive = true
    @AppStorage(GuestDisplaySettings.bandChatInAppAlertsKey) private var inAppAlertsEnabled = true
    @AppStorage(GuestDisplaySettings.bandChatCompactKey) private var compactChatEnabled = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(String(localized: "Unread badge"), isOn: $badgesEnabled)
                    Toggle(String(localized: "In-app banner"), isOn: $inAppAlertsEnabled)
                    Toggle(String(localized: "Haptic pulse"), isOn: $hapticsEnabled)
                    Toggle(String(localized: "Sound"), isOn: $soundsEnabled)
                } header: {
                    Text(String(localized: "Notifications"))
                } footer: {
                    Text(String(localized: "Only on this device. Banners appear when chat is closed."))
                }

                Section {
                    Toggle(String(localized: "Quiet during Live"), isOn: $quietDuringLive)
                } header: {
                    Text(String(localized: "Stage"))
                } footer: {
                    Text(String(localized: "When Live mode is on, skip banner, haptic, and sound so the stage stays clear. The unread badge still updates if enabled."))
                }

                Section {
                    Toggle(String(localized: "Compact chat"), isOn: $compactChatEnabled)
                } header: {
                    Text(String(localized: "Layout"))
                } footer: {
                    Text(String(localized: "Compact chat opens as a side panel (iPad/Mac) or half sheet (iPhone) so the chord stage stays visible."))
                }
            }
            .navigationTitle(String(localized: "Chat settings"))
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Medium detent sheet chrome so the chord peeks behind chat on iPhone.
struct BandChatCompactSheetChrome: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        if enabled {
            content
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// Narrow trailing overlay used on iPad / Mac when Compact chat is on.
struct BandChatCompactSidePanel: View {
    @Bindable var viewModel: SessionViewModel
    var onClose: () -> Void

    private let panelWidth: CGFloat = 280

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
                .accessibilityLabel(String(localized: "Close"))

            BandChatSheet(viewModel: viewModel, onClose: onClose)
                .frame(width: panelWidth)
                .frame(maxHeight: .infinity)
                .background(AppTheme.background.opacity(0.97))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.ringStroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 18, x: -4, y: 0)
                .padding(.trailing, 10)
                .padding(.vertical, 10)
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
        .accessibilityAddTraits(.isModal)
    }
}
