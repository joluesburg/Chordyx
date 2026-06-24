//
//  SongSheetOCR.swift
//  Chordyx
//

import Foundation
import Vision
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

enum SongSheetOCR {

    static func recognizeText(from imageData: Data) async throws -> String {
        #if canImport(UIKit)
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
            throw SongImportError.noContentFound
        }
        return try await recognizeText(in: cgImage)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: imageData) else {
            throw SongImportError.noContentFound
        }
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            throw SongImportError.noContentFound
        }
        return try await recognizeText(in: cgImage)
        #else
        throw SongImportError.noContentFound
        #endif
    }

    private static func recognizeText(in cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let text = lines.joined(separator: "\n")
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continuation.resume(throwing: SongImportError.noContentFound)
                } else {
                    continuation.resume(returning: text)
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["es-ES", "es-MX", "en-US", "pt-BR"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
