//
//  SongImportView.swift
//  Chordyx
//

import SwiftUI
import PhotosUI
#if os(iOS)
import UIKit
import VisionKit
#endif

private enum ImportMode: String, CaseIterable, Identifiable {
    case search
    case website
    case scan
    case paste

    var id: String { rawValue }

    var label: String {
        switch self {
        case .search: String(localized: "Search")
        case .website: String(localized: "Website")
        case .scan: String(localized: "Camera")
        case .paste: String(localized: "Paste")
        }
    }

    var icon: String {
        switch self {
        case .search: "magnifyingglass"
        case .website: "globe"
        case .scan: "camera.viewfinder"
        case .paste: "doc.on.clipboard"
        }
    }
}

private enum ImportStep {
    case source
    case review
    case saved
}

struct SongImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: SessionViewModel
    @Bindable var store: ProgressionStore

    @AppStorage("lastImportMode") private var lastImportModeRaw = ImportMode.search.rawValue
    @State private var importService = SongImportService()
    @State private var mode: ImportMode = .search
    @State private var importStep: ImportStep = .source
    @State private var urlText = ""
    @State private var pastedText = ""
    @State private var songTitle = ""
    @State private var artistName = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showDocumentScanner = false
    @State private var reviewTitle = ""
    @State private var reviewKey: MusicalKey = .C
    @State private var reviewTempoText = "100"
    @State private var savedProgression: SavedProgression?
    @State private var duplicateTarget: SavedProgression?
    @State private var pendingHostAfterSave = false
    @State private var showDuplicateDialog = false
    @State private var lastOCRText = ""
    @State private var showRawOCRSource = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch importStep {
                        case .source:
                            introCard
                            modePicker
                            sourcePanel
                            if importService.isLoading || importService.isSearching {
                                loadingRow
                            }
                            if let error = importService.errorMessage {
                                errorBanner(error)
                            }
                        case .review:
                            if let draft = importService.draft {
                                reviewStep(draft)
                            }
                        case .saved:
                            if let saved = savedProgression {
                                SongImportSavedSuccessView(
                                    saved: saved,
                                    onHost: { hostSavedProgression(saved) },
                                    onImportAnother: { resetForAnotherImport() },
                                    onDone: { dismiss() }
                                )
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(importStep == .saved ? "Import Complete" : "Import Song")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(importStep == .saved ? "Close" : "Cancel") {
                        if importStep == .review {
                            importStep = .source
                            importService.draft = nil
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundStyle(AppTheme.accent)
                }
                if importStep == .review {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Back") {
                            importStep = .source
                            importService.draft = nil
                        }
                        .foregroundStyle(AppTheme.accent)
                    }
                }
            }
            .confirmationDialog(
                "Song Already in Library",
                isPresented: $showDuplicateDialog,
                titleVisibility: .visible
            ) {
                Button("Replace Existing") {
                    if let draft = importService.draft {
                        performSave(draft: draft, replace: true, forceUniqueName: false)
                    }
                }
                Button("Save as New") {
                    if let draft = importService.draft {
                        performSave(draft: draft, replace: false, forceUniqueName: true)
                    }
                }
                Button("Cancel", role: .cancel) {
                    duplicateTarget = nil
                }
            } message: {
                if let duplicateTarget {
                    Text("“\(duplicateTarget.name)” is already saved. Replace it with this import, or save under a new name.")
                }
            }
            .onAppear {
                if let restored = ImportMode(rawValue: lastImportModeRaw) {
                    mode = restored
                }
            }
            .onChange(of: mode) { _, newMode in
                lastImportModeRaw = newMode.rawValue
            }
            .onChange(of: importService.draft) { _, draft in
                guard let draft else { return }
                beginReview(with: draft)
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $showDocumentScanner) {
                SongDocumentScanner { images in
                    Task { await processScannedImages(images) }
                }
            }
            #endif
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task { await processPhotoItem(item) }
            }
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ready in seconds", systemImage: "bolt.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.accent)

            Text("Search the web, pick a chart, preview section rings, then save or host.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var modePicker: some View {
        Picker("Source", selection: $mode) {
            ForEach(ImportMode.allCases) { item in
                Label(item.label, systemImage: item.icon).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var sourcePanel: some View {
        switch mode {
        case .search:
            searchPanel
        case .website:
            websitePanel
        case .scan:
            scanPanel
        case .paste:
            pastePanel
        }
    }

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Song title")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            TextField("e.g. Tu fidelidad", text: $songTitle)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .textInputAutocapitalization(.words)
                #endif

            Text("Artist (optional)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            TextField("e.g. Marcos Witt", text: $artistName)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .textInputAutocapitalization(.words)
                #endif

            Text("Searches chord sites on the internet. Pick a match to preview before saving.")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

            Button {
                Task { await importService.findCharts(title: songTitle, artist: artistName) }
            } label: {
                Label("Search for Chords", systemImage: "sparkle.magnifyingglass")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .disabled(songTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || importService.isLoading || importService.isSearching)

            if !importService.searchResults.isEmpty {
                Text("Results")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.top, 4)

                VStack(spacing: 8) {
                    ForEach(importService.searchResults) { result in
                        Button {
                            Task { await importService.importSearchResult(result) }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(result.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.textPrimary)
                                        .lineLimit(1)
                                    Text(result.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "eye.fill")
                                    .foregroundStyle(AppTheme.accent)
                            }
                            .padding(12)
                            .background(AppTheme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .disabled(importService.isLoading)
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var websitePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Song URL")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            TextField("https://www.example.com/chord-chart", text: $urlText)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                #endif

            ClipboardPasteButton(label: "Paste URL from clipboard", systemImage: "doc.on.clipboard") { text in
                urlText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if urlText.isEmpty, let clipURL = ImportClipboard.likelyURL {
                Button {
                    urlText = clipURL
                } label: {
                    Label("Use clipboard URL", systemImage: "link")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(AppTheme.accent)
            }

            Text("Works with La Cuerda, Ultimate Guitar, and pages with chord charts in plain text.")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

            Button {
                Task { await importService.importFromURL(urlText) }
            } label: {
                Label("Download & Parse", systemImage: "arrow.down.circle.fill")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || importService.isLoading)
        }
        .padding(16)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var scanPanel: some View {
        VStack(spacing: 14) {
            Text("Photograph a printed chord sheet or screen. Chordyx reads the chords and lyrics with on-device OCR.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)

            #if os(iOS)
            if VNDocumentCameraViewController.isSupported {
                Button {
                    showDocumentScanner = true
                } label: {
                    Label("Scan Chord Sheet", systemImage: "doc.viewfinder.fill")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
            }
            #endif

            PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                Label("Choose Photo", systemImage: "photo.on.rectangle.angled")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .foregroundStyle(AppTheme.textPrimary)

            TextField("Song title (optional)", text: $songTitle)
                .textFieldStyle(.roundedBorder)
        }
        .padding(16)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var pastePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Song title", text: $songTitle)
                .textFieldStyle(.roundedBorder)

            Text("Paste chord/lyric text")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            TextEditor(text: $pastedText)
                .frame(minHeight: 180)
                .padding(8)
                .background(AppTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.ringStroke.opacity(0.35), lineWidth: 1)
                )

            ClipboardPasteButton(label: "Paste chart from clipboard", systemImage: "doc.on.clipboard") { text in
                pastedText = text
            }

            Text("Supports [Am] inline chords, chord lines above lyrics, and {Am} ChordPro format.")
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

            Button {
                let title = songTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                importService.importFromPlainText(
                    pastedText,
                    title: title.isEmpty ? String(localized: "Imported Song") : title
                )
            } label: {
                Label("Parse Text", systemImage: "text.magnifyingglass")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || importService.isLoading)
        }
        .padding(16)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var loadingRow: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(importService.isSearching ? "Searching the web for chords…" : "Reading chords and lyrics…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func reviewStep(_ draft: SongImportDraft) -> some View {
        let quality = SongImportQuality.assess(draft)

        return VStack(alignment: .leading, spacing: 16) {
            SongImportQualityCard(quality: quality, warnings: draft.warnings)

            SongImportReviewFields(
                title: $reviewTitle,
                key: $reviewKey,
                tempoText: $reviewTempoText,
                artist: draft.artist
            )

            if !draft.sections.isEmpty {
                SongImportSectionReviewList(draft: draft)
            } else if draft.chords.count > 6 {
                Text("No sections detected — the full song will use one ring with \(draft.chords.count) chords. Add sections in the editor after saving.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(12)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            lyricsPreview(draft)

            if !lastOCRText.isEmpty {
                DisclosureGroup("Edit source text", isExpanded: $showRawOCRSource) {
                    TextEditor(text: $lastOCRText)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Button {
                        let title = reviewTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        importService.importFromPlainText(
                            lastOCRText,
                            title: title.isEmpty ? draft.title : title
                        )
                    } label: {
                        Label("Re-parse Text", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(AppTheme.accent)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(12)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            reviewActionButtons(draft)
        }
    }

    private func lyricsPreview(_ draft: SongImportDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lyrics preview")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            ForEach(draft.lyricsLines.prefix(5)) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let symbol = line.chordSymbol {
                        Text(symbol)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.accentSecondary)
                            .frame(minWidth: 36, alignment: .leading)
                    }
                    Text(line.text)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)
                }
            }

            if draft.lyricsLines.count > 5 {
                Text("+\(draft.lyricsLines.count - 5) more lines")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(12)
        .background(AppTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func reviewActionButtons(_ draft: SongImportDraft) -> some View {
        VStack(spacing: 12) {
            Button {
                attemptSave(draft: draft, host: true)
            } label: {
                Label("Save & Host Session", systemImage: "play.fill")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)

            Button {
                attemptSave(draft: draft, host: false)
            } label: {
                Label("Save to Library", systemImage: "bookmark.fill")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .foregroundStyle(AppTheme.textPrimary)
        }
    }

    private func beginReview(with draft: SongImportDraft) {
        reviewTitle = draft.title
        reviewKey = draft.key
        reviewTempoText = draft.tempoBPM.map { String(Int($0)) } ?? "100"
        importStep = .review
    }

    private func attemptSave(draft: SongImportDraft, host: Bool) {
        pendingHostAfterSave = host
        let trimmed = reviewTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? draft.title : trimmed
        if let existing = store.findDuplicate(named: name) {
            duplicateTarget = existing
            showDuplicateDialog = true
            return
        }
        performSave(draft: draft, replace: false, forceUniqueName: false)
    }

    private func performSave(draft: SongImportDraft, replace: Bool, forceUniqueName: Bool) {
        var finalName = reviewTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if finalName.isEmpty { finalName = draft.title }
        if forceUniqueName {
            finalName = store.uniqueImportName(basedOn: finalName)
        }

        let tempo = Double(reviewTempoText.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? draft.tempoBPM
            ?? 100

        let progression = draft.makeSavedProgression(
            title: finalName,
            key: reviewKey,
            tempoBPM: tempo,
            existingID: replace ? duplicateTarget?.id : nil
        )

        let saved: SavedProgression
        if replace, let existing = duplicateTarget {
            saved = store.replace(progression, keepingID: existing)
        } else {
            saved = store.save(progression)
        }

        savedProgression = saved
        duplicateTarget = nil

        if pendingHostAfterSave {
            hostSavedProgression(saved)
        } else {
            importStep = .saved
        }
    }

    private func hostSavedProgression(_ saved: SavedProgression) {
        let guide = makeImportGuide(for: importService.draft, saved: saved)
        viewModel.hostSession(from: saved, importGuide: guide)
        dismiss()
    }

    private func makeImportGuide(
        for draft: SongImportDraft?,
        saved: SavedProgression
    ) -> SessionViewModel.ImportSessionGuide? {
        guard saved.sections.count >= 2 else { return nil }
        let breakdown = SongSectionAnalyzer.sectionBreakdown(chords: saved.chords, sections: saved.sections)
        let ringHints = breakdown.map { "\($0.section.name): \($0.chords.count)" }.joined(separator: " · ")
        var message = String(format: String(localized: "Tap sections above to switch rings while playing. %@"), ringHints)
        if draft?.warnings.contains(where: { $0.contains("Verse ring was added") }) == true {
            message += " " + String(localized: "We added a Verse — adjust in Lyrics & Sections if needed.")
        }
        return SessionViewModel.ImportSessionGuide(
            title: String(localized: "Section rings ready"),
            message: message
        )
    }

    private func resetForAnotherImport() {
        importService.reset()
        savedProgression = nil
        duplicateTarget = nil
        pendingHostAfterSave = false
        lastOCRText = ""
        showRawOCRSource = false
        importStep = .source
    }

    #if os(iOS)
    private func processScannedImages(_ images: [UIImage]) async {
        importService.isLoading = true
        importService.errorMessage = nil
        importService.draft = nil
        defer { importService.isLoading = false }

        var combined = ""
        do {
            for image in images {
                guard let data = image.jpegData(compressionQuality: 0.9) else { continue }
                let text = try await SongSheetOCR.recognizeText(from: data)
                combined += text + "\n"
            }
            lastOCRText = combined
            let title = songTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            importService.importFromPlainText(
                combined,
                title: title.isEmpty ? String(localized: "Scanned Song") : title
            )
        } catch let error as SongImportError {
            importService.errorMessage = error.localizedDescription
        } catch {
            importService.errorMessage = error.localizedDescription
        }
    }
    #endif

    private func processPhotoItem(_ item: PhotosPickerItem) async {
        importService.isLoading = true
        importService.errorMessage = nil
        importService.draft = nil
        defer { importService.isLoading = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw SongImportError.noContentFound
            }
            let text = try await SongSheetOCR.recognizeText(from: data)
            lastOCRText = text
            let title = songTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            importService.importFromPlainText(
                text,
                title: title.isEmpty ? String(localized: "Scanned Song") : title
            )
        } catch let error as SongImportError {
            importService.errorMessage = error.localizedDescription
        } catch {
            importService.errorMessage = error.localizedDescription
        }
    }
}

#if os(iOS)
private struct SongDocumentScanner: UIViewControllerRepresentable {
    var onScan: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: SongDocumentScanner

        init(parent: SongDocumentScanner) {
            self.parent = parent
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            for index in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: index))
            }
            parent.onScan(images)
            parent.dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.dismiss()
        }
    }
}
#endif
