//
//  GlobalMusicGenre.swift
//  Chordyx
//
//  Worldwide genre taxonomy for live identification — separate from accompaniment grooves.
//

import Foundation

enum GlobalMusicRegion: String, CaseIterable, Sendable, Codable, Identifiable {
    case popRockDance
    case jazzBlues
    case worshipGospel
    case latinCaribbean
    case northAmericaRoots
    case europe
    case africa
    case middleEast
    case southAsia
    case eastAsia
    case oceaniaPacific
    case classicalArt

    var id: String { rawValue }

    var label: String {
        switch self {
        case .popRockDance: String(localized: "Pop, rock & dance")
        case .jazzBlues: String(localized: "Jazz & blues")
        case .worshipGospel: String(localized: "Worship & gospel")
        case .latinCaribbean: String(localized: "Latin & Caribbean")
        case .northAmericaRoots: String(localized: "North American roots")
        case .europe: String(localized: "Europe")
        case .africa: String(localized: "Africa")
        case .middleEast: String(localized: "Middle East")
        case .southAsia: String(localized: "South Asia")
        case .eastAsia: String(localized: "East Asia")
        case .oceaniaPacific: String(localized: "Oceania & Pacific")
        case .classicalArt: String(localized: "Classical & art music")
        }
    }

    var icon: String {
        switch self {
        case .popRockDance: "waveform"
        case .jazzBlues: "saxophone"
        case .worshipGospel: "hands.clap"
        case .latinCaribbean: "figure.dance"
        case .northAmericaRoots: "guitars"
        case .europe: "building.columns"
        case .africa: "globe.africa"
        case .middleEast: "moon.stars"
        case .southAsia: "sparkles"
        case .eastAsia: "sun.max"
        case .oceaniaPacific: "leaf"
        case .classicalArt: "music.quarternote.3"
        }
    }
}

struct GlobalGenreFingerprint: Sendable {
    var tempoRange: ClosedRange<Double>
    var tempoPeak: Double
    var syncopationRange: ClosedRange<Double> = 0...1
    var syncopationPeak: Double = 0.35
    var changeRateRange: ClosedRange<Double> = 0...24
    var complexityRange: ClosedRange<Double> = 0...5
    var minor7Weight: Double = 0
    var dom7Weight: Double = 0
    var maj7Weight: Double = 0
    var triadWeight: Double = 0
    var extendedWeight: Double = 0
    var powerWeight: Double = 0
    var waltzWeight: Double = 0
    /// Closest live accompaniment groove when drums are enabled.
    var anchorGroove: LiveMusicStyle
    /// Optional Latin pattern engine tags for extra boost.
    var latinPatternTags: [String] = []
}

struct GlobalMusicGenre: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let region: GlobalMusicRegion
    let family: String
    let fingerprint: GlobalGenreFingerprint

    var closestGroove: LiveMusicStyle { fingerprint.anchorGroove }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: GlobalMusicGenre, rhs: GlobalMusicGenre) -> Bool {
        lhs.id == rhs.id
    }
}

struct GlobalGenreCandidate: Sendable, Identifiable {
    let genre: GlobalMusicGenre
    let score: Double

    var id: String { genre.id }
}

struct GlobalGenreAnalysis: Sendable {
    var primary: GlobalMusicGenre?
    var confidence: Double = 0
    var region: GlobalMusicRegion?
    var regionConfidence: Double = 0
    var alternatives: [GlobalGenreCandidate] = []
    var matchedPatternLabel: String?

    static let empty = GlobalGenreAnalysis()

    var displayLabel: String {
        primary?.label ?? String(localized: "Listening…")
    }

    var displaySubtitle: String {
        guard let primary else { return "" }
        if let region {
            return "\(region.label) · \(primary.family)"
        }
        return primary.family
    }
}

struct GlobalGenrePerformanceSnapshot: Sendable {
    var bpm: Double
    var syncopation: Double
    var chordChangeRate: Double
    var avgHarmonicComplexity: Double
    var minor7Ratio: Double
    var dom7Ratio: Double
    var maj7Ratio: Double
    var triadRatio: Double
    var extendedRatio: Double
    var powerRatio: Double
    var susRatio: Double
    var waltzLikelihood: Double
    var onsetDensity: Double
    var spectralBrightness: Double
    var lowEnergyRatio: Double
    var liveStyleScores: [LiveMusicStyle: Double]
    var latinAnalysis: LatinRhythmAnalysis
    var audioStyleProbabilities: [LiveMusicStyle: Double]

    static let empty = GlobalGenrePerformanceSnapshot(
        bpm: 100,
        syncopation: 0,
        chordChangeRate: 0,
        avgHarmonicComplexity: 0,
        minor7Ratio: 0,
        dom7Ratio: 0,
        maj7Ratio: 0,
        triadRatio: 0,
        extendedRatio: 0,
        powerRatio: 0,
        susRatio: 0,
        waltzLikelihood: 0,
        onsetDensity: 0,
        spectralBrightness: 0.5,
        lowEnergyRatio: 0.33,
        liveStyleScores: [:],
        latinAnalysis: .empty,
        audioStyleProbabilities: [:]
    )
}

enum GlobalMusicGenreCatalog {
    static let all: [GlobalMusicGenre] = buildCatalog()

    static func genre(id: String) -> GlobalMusicGenre? {
        all.first { $0.id == id }
    }

    static func genres(in region: GlobalMusicRegion) -> [GlobalMusicGenre] {
        all.filter { $0.region == region }
    }

    private struct GenreOpts {
        var sync: ClosedRange<Double> = 0...1
        var syncPeak: Double = 0.35
        var change: ClosedRange<Double> = 0...24
        var complexity: ClosedRange<Double> = 0...5
        var m7: Double = 0
        var d7: Double = 0
        var maj7: Double = 0
        var triad: Double = 0
        var ext: Double = 0
        var power: Double = 0
        var waltz: Double = 0
        var latinTags: [String] = []
    }

    private static func g(
        _ id: String,
        _ label: String,
        region: GlobalMusicRegion,
        family: String,
        tempo: ClosedRange<Double>,
        peak: Double,
        groove: LiveMusicStyle,
        _ opts: GenreOpts = GenreOpts()
    ) -> GlobalMusicGenre {
        GlobalMusicGenre(
            id: id,
            label: String(localized: String.LocalizationValue(label)),
            region: region,
            family: String(localized: String.LocalizationValue(family)),
            fingerprint: GlobalGenreFingerprint(
                tempoRange: tempo,
                tempoPeak: peak,
                syncopationRange: opts.sync,
                syncopationPeak: opts.syncPeak,
                changeRateRange: opts.change,
                complexityRange: opts.complexity,
                minor7Weight: opts.m7,
                dom7Weight: opts.d7,
                maj7Weight: opts.maj7,
                triadWeight: opts.triad,
                extendedWeight: opts.ext,
                powerWeight: opts.power,
                waltzWeight: opts.waltz,
                anchorGroove: groove,
                latinPatternTags: opts.latinTags
            )
        )
    }

    private static func buildCatalog() -> [GlobalMusicGenre] {
        var genres: [GlobalMusicGenre] = []

        // MARK: Pop, rock & dance
        genres += [
            g("pop", "Pop", region: .popRockDance, family: "Pop", tempo: 92...132, peak: 112, groove: .popRock, GenreOpts(sync: 0...0.42, triad: 0.5)),
            g("indiePop", "Indie pop", region: .popRockDance, family: "Pop", tempo: 88...128, peak: 108, groove: .popRock, GenreOpts(sync: 0.08...0.45, triad: 0.42, ext: 0.15)),
            g("synthPop", "Synth pop", region: .popRockDance, family: "Pop", tempo: 100...130, peak: 118, groove: .edmPulse, GenreOpts(sync: 0...0.35, triad: 0.45)),
            g("dancePop", "Dance pop", region: .popRockDance, family: "Pop", tempo: 112...132, peak: 124, groove: .edmPulse, GenreOpts(sync: 0...0.38, triad: 0.4)),
            g("rock", "Rock", region: .popRockDance, family: "Rock", tempo: 100...150, peak: 124, groove: .rockDrive, GenreOpts(sync: 0...0.4, triad: 0.45, power: 0.35)),
            g("altRock", "Alternative rock", region: .popRockDance, family: "Rock", tempo: 96...140, peak: 118, groove: .rockDrive, GenreOpts(sync: 0.05...0.42, triad: 0.4, power: 0.25)),
            g("punkRock", "Punk rock", region: .popRockDance, family: "Rock", tempo: 140...190, peak: 168, groove: .rockDrive, GenreOpts(sync: 0...0.35, triad: 0.5, power: 0.45)),
            g("hardRock", "Hard rock", region: .popRockDance, family: "Rock", tempo: 108...160, peak: 132, groove: .rockDrive, GenreOpts(sync: 0...0.38, triad: 0.35, power: 0.55)),
            g("metal", "Heavy metal", region: .popRockDance, family: "Rock", tempo: 120...180, peak: 148, groove: .rockDrive, GenreOpts(sync: 0...0.32, power: 0.65)),
            g("progRock", "Progressive rock", region: .popRockDance, family: "Rock", tempo: 88...150, peak: 118, groove: .rockDrive, GenreOpts(sync: 0.1...0.5, complexity: 1.5...5, ext: 0.35)),
            g("funk", "Funk", region: .popRockDance, family: "Funk & soul", tempo: 92...128, peak: 108, groove: .funkGroove, GenreOpts(sync: 0.38...0.85, syncPeak: 0.58, m7: 0.25, d7: 0.35)),
            g("disco", "Disco", region: .popRockDance, family: "Dance", tempo: 112...132, peak: 124, groove: .edmPulse, GenreOpts(sync: 0...0.35, triad: 0.4)),
            g("rb", "R&B", region: .popRockDance, family: "Funk & soul", tempo: 72...108, peak: 88, groove: .rbSoul, GenreOpts(sync: 0.25...0.55, m7: 0.35, maj7: 0.25, ext: 0.2)),
            g("soul", "Soul", region: .popRockDance, family: "Funk & soul", tempo: 72...112, peak: 92, groove: .rbSoul, GenreOpts(sync: 0.2...0.5, m7: 0.3, maj7: 0.28)),
            g("motown", "Motown", region: .popRockDance, family: "Funk & soul", tempo: 96...128, peak: 112, groove: .rbSoul, GenreOpts(sync: 0.15...0.45, m7: 0.25, triad: 0.4)),
            g("neoSoul", "Neo-soul", region: .popRockDance, family: "Funk & soul", tempo: 68...102, peak: 84, groove: .rbSoul, GenreOpts(sync: 0.28...0.58, m7: 0.38, maj7: 0.3, ext: 0.25)),
            g("hipHop", "Hip-hop", region: .popRockDance, family: "Hip-hop", tempo: 72...104, peak: 88, groove: .funkGroove, GenreOpts(sync: 0.35...0.72, syncPeak: 0.52, change: 0...14)),
            g("trap", "Trap", region: .popRockDance, family: "Hip-hop", tempo: 130...160, peak: 140, groove: .edmPulse, GenreOpts(sync: 0.2...0.55, change: 0...12)),
            g("edm", "EDM", region: .popRockDance, family: "Electronic", tempo: 118...150, peak: 128, groove: .edmPulse, GenreOpts(sync: 0...0.28, triad: 0.35)),
            g("house", "House", region: .popRockDance, family: "Electronic", tempo: 118...132, peak: 124, groove: .edmPulse, GenreOpts(sync: 0...0.32)),
            g("techno", "Techno", region: .popRockDance, family: "Electronic", tempo: 124...140, peak: 132, groove: .edmPulse, GenreOpts(sync: 0...0.25)),
            g("trance", "Trance", region: .popRockDance, family: "Electronic", tempo: 128...150, peak: 138, groove: .edmPulse, GenreOpts(sync: 0...0.3)),
            g("dubstep", "Dubstep", region: .popRockDance, family: "Electronic", tempo: 138...150, peak: 140, groove: .edmPulse, GenreOpts(sync: 0.15...0.45)),
            g("dnb", "Drum & bass", region: .popRockDance, family: "Electronic", tempo: 160...180, peak: 174, groove: .edmPulse, GenreOpts(sync: 0.2...0.5)),
            g("ambient", "Ambient", region: .popRockDance, family: "Electronic", tempo: 48...80, peak: 64, groove: .softPulse, GenreOpts(sync: 0...0.25, change: 0...6, maj7: 0.3)),
            g("singerSongwriter", "Singer-songwriter", region: .popRockDance, family: "Folk pop", tempo: 72...108, peak: 92, groove: .popRock, GenreOpts(sync: 0...0.35, change: 0...10, triad: 0.45)),
        ]

        // MARK: Jazz & blues
        genres += [
            g("jazzSwing", "Jazz swing", region: .jazzBlues, family: "Jazz", tempo: 100...200, peak: 140, groove: .jazzSwing, GenreOpts(sync: 0.28...0.62, complexity: 2...5, m7: 0.35, maj7: 0.25, ext: 0.4)),
            g("bebop", "Bebop", region: .jazzBlues, family: "Jazz", tempo: 140...220, peak: 168, groove: .jazzSwing, GenreOpts(sync: 0.35...0.7, complexity: 2.5...5, m7: 0.4, ext: 0.45)),
            g("coolJazz", "Cool jazz", region: .jazzBlues, family: "Jazz", tempo: 88...140, peak: 112, groove: .jazzSwing, GenreOpts(sync: 0.2...0.5, m7: 0.3, maj7: 0.35)),
            g("smoothJazz", "Smooth jazz", region: .jazzBlues, family: "Jazz", tempo: 80...120, peak: 96, groove: .rbSoul, GenreOpts(sync: 0.15...0.45, maj7: 0.38, ext: 0.25)),
            g("jazzFusion", "Jazz fusion", region: .jazzBlues, family: "Jazz", tempo: 96...150, peak: 118, groove: .funkGroove, GenreOpts(sync: 0.3...0.65, m7: 0.35, ext: 0.45)),
            g("latinJazz", "Latin jazz", region: .jazzBlues, family: "Jazz", tempo: 100...148, peak: 120, groove: .bossaNova, GenreOpts(sync: 0.35...0.72, m7: 0.35, ext: 0.3, latinTags: ["bossa", "salsa"])),
            g("blues", "Blues", region: .jazzBlues, family: "Blues", tempo: 72...118, peak: 92, groove: .bluesShuffle, GenreOpts(sync: 0.25...0.55, d7: 0.55)),
            g("deltaBlues", "Delta blues", region: .jazzBlues, family: "Blues", tempo: 60...96, peak: 76, groove: .bluesShuffle, GenreOpts(sync: 0.2...0.5, d7: 0.5)),
            g("chicagoBlues", "Chicago blues", region: .jazzBlues, family: "Blues", tempo: 88...128, peak: 108, groove: .bluesShuffle, GenreOpts(sync: 0.28...0.58, d7: 0.52)),
            g("bluesRock", "Blues rock", region: .jazzBlues, family: "Blues", tempo: 96...140, peak: 118, groove: .rockDrive, GenreOpts(sync: 0.2...0.48, d7: 0.4, power: 0.35)),
        ]

        // MARK: Worship & gospel
        genres += [
            g("contemporaryWorship", "Contemporary worship", region: .worshipGospel, family: "Worship", tempo: 58...108, peak: 78, groove: .worshipBallad, GenreOpts(sync: 0...0.38, change: 0...12, maj7: 0.35, ext: 0.25)),
            g("worshipBallad", "Worship ballad", region: .worshipGospel, family: "Worship", tempo: 52...88, peak: 72, groove: .worshipBallad, GenreOpts(sync: 0...0.32, change: 0...8, maj7: 0.38, ext: 0.22)),
            g("gospel", "Gospel", region: .worshipGospel, family: "Gospel", tempo: 88...132, peak: 104, groove: .gospelGroove, GenreOpts(sync: 0.22...0.55, d7: 0.3, triad: 0.35)),
            g("praiseGospel", "Praise gospel", region: .worshipGospel, family: "Gospel", tempo: 108...148, peak: 128, groove: .gospelGroove, GenreOpts(sync: 0.18...0.48, change: 8...20, d7: 0.28)),
            g("spiritual", "Spiritual / hymnal", region: .worshipGospel, family: "Hymnal", tempo: 56...96, peak: 76, groove: .softPulse, GenreOpts(sync: 0...0.28, triad: 0.45, waltz: 0.2)),
            g("softBallad", "Soft ballad", region: .worshipGospel, family: "Ballad", tempo: 48...78, peak: 64, groove: .softPulse, GenreOpts(sync: 0...0.25, change: 0...6, maj7: 0.3)),
        ]

        // MARK: Latin & Caribbean
        genres += [
            g("salsa", "Salsa", region: .latinCaribbean, family: "Caribbean", tempo: 88...148, peak: 112, groove: .salsa, GenreOpts(sync: 0.35...0.75, m7: 0.3, d7: 0.28, latinTags: ["salsa", "clave"])),
            g("mambo", "Mambo", region: .latinCaribbean, family: "Caribbean", tempo: 100...160, peak: 132, groove: .salsa, GenreOpts(sync: 0.38...0.72, d7: 0.32, latinTags: ["salsa"])),
            g("chachacha", "Cha-cha-chá", region: .latinCaribbean, family: "Caribbean", tempo: 108...132, peak: 120, groove: .salsa, GenreOpts(sync: 0.32...0.62, latinTags: ["salsa"])),
            g("sonCubano", "Son cubano", region: .latinCaribbean, family: "Caribbean", tempo: 88...128, peak: 104, groove: .salsa, GenreOpts(sync: 0.35...0.68, m7: 0.28, latinTags: ["salsa"])),
            g("timba", "Timba", region: .latinCaribbean, family: "Caribbean", tempo: 96...140, peak: 118, groove: .songo, GenreOpts(sync: 0.42...0.78, m7: 0.32, ext: 0.3, latinTags: ["songo"])),
            g("montuno", "Montuno", region: .latinCaribbean, family: "Caribbean", tempo: 92...138, peak: 108, groove: .montuno, GenreOpts(sync: 0.42...0.82, syncPeak: 0.62, m7: 0.28, d7: 0.25, latinTags: ["montuno", "clave"])),
            g("guaguanco", "Guaguancó", region: .latinCaribbean, family: "Caribbean", tempo: 88...128, peak: 108, groove: .salsa, GenreOpts(sync: 0.45...0.8, latinTags: ["salsa"])),
            g("merengue", "Merengue", region: .latinCaribbean, family: "Caribbean", tempo: 118...178, peak: 140, groove: .merengue, GenreOpts(sync: 0...0.38, change: 10...22, triad: 0.45, latinTags: ["merengue"])),
            g("bachata", "Bachata", region: .latinCaribbean, family: "Caribbean", tempo: 108...140, peak: 124, groove: .bolero, GenreOpts(sync: 0.22...0.52, triad: 0.4, latinTags: ["bolero"])),
            g("dembow", "Dembow", region: .latinCaribbean, family: "Urban Caribbean", tempo: 92...108, peak: 98, groove: .reggaeOneDrop, GenreOpts(sync: 0.35...0.65)),
            g("reggaeton", "Reggaetón", region: .latinCaribbean, family: "Urban Caribbean", tempo: 88...102, peak: 94, groove: .reggaeOneDrop, GenreOpts(sync: 0.38...0.68, change: 0...12)),
            g("cumbia", "Cumbia", region: .latinCaribbean, family: "Latin America", tempo: 88...118, peak: 102, groove: .merengue, GenreOpts(sync: 0.28...0.58, triad: 0.4, latinTags: ["cumbia"])),
            g("vallenato", "Vallenato", region: .latinCaribbean, family: "Latin America", tempo: 92...128, peak: 108, groove: .countryTrain, GenreOpts(sync: 0.2...0.48, triad: 0.42)),
            g("champeta", "Champeta", region: .latinCaribbean, family: "Latin America", tempo: 96...124, peak: 108, groove: .reggaeOneDrop, GenreOpts(sync: 0.35...0.65)),
            g("bossaNova", "Bossa nova", region: .latinCaribbean, family: "Brazil", tempo: 100...148, peak: 124, groove: .bossaNova, GenreOpts(sync: 0.32...0.62, m7: 0.3, maj7: 0.35, latinTags: ["bossa"])),
            g("samba", "Samba", region: .latinCaribbean, family: "Brazil", tempo: 100...140, peak: 120, groove: .bossaNova, GenreOpts(sync: 0.38...0.72, latinTags: ["bossa"])),
            g("pagode", "Pagode", region: .latinCaribbean, family: "Brazil", tempo: 92...128, peak: 108, groove: .bossaNova, GenreOpts(sync: 0.35...0.65, m7: 0.28)),
            g("forro", "Forró", region: .latinCaribbean, family: "Brazil", tempo: 108...140, peak: 124, groove: .countryTrain, GenreOpts(sync: 0.28...0.55, triad: 0.4)),
            g("mpb", "MPB", region: .latinCaribbean, family: "Brazil", tempo: 72...120, peak: 96, groove: .bossaNova, GenreOpts(sync: 0.22...0.52, m7: 0.25, maj7: 0.3)),
            g("songo", "Songó", region: .latinCaribbean, family: "Caribbean", tempo: 82...138, peak: 102, groove: .songo, GenreOpts(sync: 0.38...0.72, m7: 0.3, ext: 0.28, latinTags: ["songo"])),
            g("tango", "Tango", region: .latinCaribbean, family: "Southern cone", tempo: 100...140, peak: 120, groove: .bolero, GenreOpts(sync: 0.35...0.65, m7: 0.25)),
            g("chacarera", "Chacarera", region: .latinCaribbean, family: "Southern cone", tempo: 108...140, peak: 124, groove: .countryTrain, GenreOpts(sync: 0.25...0.52, triad: 0.42)),
            g("bolero", "Bolero", region: .latinCaribbean, family: "Ballad", tempo: 56...88, peak: 72, groove: .bolero, GenreOpts(sync: 0...0.35, change: 0...8, maj7: 0.32, ext: 0.22, latinTags: ["bolero"])),
            g("ranchera", "Ranchera", region: .latinCaribbean, family: "Mexico", tempo: 72...108, peak: 88, groove: .countryTrain, GenreOpts(sync: 0.15...0.42, triad: 0.45)),
            g("mariachi", "Mariachi", region: .latinCaribbean, family: "Mexico", tempo: 96...140, peak: 120, groove: .countryTrain, GenreOpts(sync: 0.2...0.48, triad: 0.48)),
            g("norteno", "Norteño", region: .latinCaribbean, family: "Mexico", tempo: 108...148, peak: 128, groove: .countryTrain, GenreOpts(sync: 0.18...0.45, triad: 0.45)),
            g("banda", "Banda", region: .latinCaribbean, family: "Mexico", tempo: 112...152, peak: 132, groove: .merengue, GenreOpts(sync: 0.15...0.42, triad: 0.42)),
            g("plena", "Plena", region: .latinCaribbean, family: "Puerto Rico", tempo: 100...140, peak: 120, groove: .salsa, GenreOpts(sync: 0.35...0.68)),
            g("bomba", "Bomba", region: .latinCaribbean, family: "Puerto Rico", tempo: 88...128, peak: 108, groove: .salsa, GenreOpts(sync: 0.42...0.78)),
            g("reggae", "Reggae", region: .latinCaribbean, family: "Jamaica", tempo: 68...98, peak: 82, groove: .reggaeOneDrop, GenreOpts(sync: 0.35...0.65, m7: 0.3)),
            g("dancehall", "Dancehall", region: .latinCaribbean, family: "Jamaica", tempo: 88...108, peak: 96, groove: .reggaeOneDrop, GenreOpts(sync: 0.38...0.68)),
            g("ska", "Ska", region: .latinCaribbean, family: "Jamaica", tempo: 120...160, peak: 140, groove: .popRock, GenreOpts(sync: 0.28...0.55, triad: 0.35)),
            g("calypso", "Calypso", region: .latinCaribbean, family: "Trinidad", tempo: 88...128, peak: 108, groove: .reggaeOneDrop, GenreOpts(sync: 0.32...0.62)),
            g("soca", "Soca", region: .latinCaribbean, family: "Trinidad", tempo: 120...160, peak: 140, groove: .merengue, GenreOpts(sync: 0.35...0.65)),
            g("zouk", "Zouk", region: .latinCaribbean, family: "French Caribbean", tempo: 88...118, peak: 102, groove: .bolero, GenreOpts(sync: 0.32...0.58)),
            g("kompa", "Kompa", region: .latinCaribbean, family: "Haiti", tempo: 88...118, peak: 102, groove: .rbSoul, GenreOpts(sync: 0.28...0.55)),
        ]

        // MARK: North American roots
        genres += [
            g("country", "Country", region: .northAmericaRoots, family: "Country", tempo: 88...148, peak: 116, groove: .countryTrain, GenreOpts(sync: 0...0.38, triad: 0.48)),
            g("americana", "Americana", region: .northAmericaRoots, family: "Country", tempo: 80...120, peak: 96, groove: .countryTrain, GenreOpts(sync: 0.1...0.4, triad: 0.42)),
            g("bluegrass", "Bluegrass", region: .northAmericaRoots, family: "Country", tempo: 120...180, peak: 148, groove: .countryTrain, GenreOpts(sync: 0.15...0.45, triad: 0.45)),
            g("folkRock", "Folk rock", region: .northAmericaRoots, family: "Folk", tempo: 88...128, peak: 108, groove: .popRock, GenreOpts(sync: 0.1...0.4, triad: 0.42)),
            g("appalachian", "Appalachian folk", region: .northAmericaRoots, family: "Folk", tempo: 72...108, peak: 88, groove: .countryTrain, GenreOpts(sync: 0.08...0.35, triad: 0.45)),
        ]

        // MARK: Europe
        genres += [
            g("flamenco", "Flamenco", region: .europe, family: "Spain", tempo: 100...180, peak: 140, groove: .salsa, GenreOpts(sync: 0.42...0.82, syncPeak: 0.62)),
            g("fado", "Fado", region: .europe, family: "Portugal", tempo: 56...88, peak: 72, groove: .bolero, GenreOpts(sync: 0.15...0.42, m7: 0.28)),
            g("celtic", "Celtic folk", region: .europe, family: "Celtic", tempo: 96...160, peak: 132, groove: .countryTrain, GenreOpts(sync: 0.2...0.5, triad: 0.4)),
            g("irishFolk", "Irish folk", region: .europe, family: "Celtic", tempo: 120...180, peak: 148, groove: .countryTrain, GenreOpts(sync: 0.22...0.52, triad: 0.38)),
            g("klezmer", "Klezmer", region: .europe, family: "Eastern Europe", tempo: 100...160, peak: 132, groove: .jazzSwing, GenreOpts(sync: 0.35...0.68, m7: 0.25)),
            g("polka", "Polka", region: .europe, family: "Central Europe", tempo: 112...160, peak: 132, groove: .countryTrain, GenreOpts(sync: 0.15...0.42, triad: 0.42)),
            g("waltz", "Waltz", region: .europe, family: "Dance", tempo: 84...180, peak: 120, groove: .brushWaltz, GenreOpts(sync: 0...0.35, maj7: 0.25, waltz: 0.75)),
            g("euroPop", "Euro pop", region: .europe, family: "Pop", tempo: 100...132, peak: 118, groove: .popRock, GenreOpts(sync: 0...0.38, triad: 0.4)),
        ]

        // MARK: Africa
        genres += [
            g("afrobeat", "Afrobeat", region: .africa, family: "West Africa", tempo: 96...128, peak: 112, groove: .funkGroove, GenreOpts(sync: 0.38...0.72, m7: 0.28)),
            g("highlife", "Highlife", region: .africa, family: "West Africa", tempo: 88...128, peak: 108, groove: .reggaeOneDrop, GenreOpts(sync: 0.32...0.62, triad: 0.35)),
            g("soukous", "Soukous", region: .africa, family: "Central Africa", tempo: 108...148, peak: 128, groove: .merengue, GenreOpts(sync: 0.35...0.68)),
            g("amapiano", "Amapiano", region: .africa, family: "South Africa", tempo: 108...118, peak: 112, groove: .edmPulse, GenreOpts(sync: 0.32...0.58)),
            g("afroHouse", "Afro house", region: .africa, family: "South Africa", tempo: 118...128, peak: 124, groove: .edmPulse, GenreOpts(sync: 0.28...0.55)),
            g("makossa", "Makossa", region: .africa, family: "Cameroon", tempo: 108...132, peak: 120, groove: .funkGroove, GenreOpts(sync: 0.35...0.65)),
        ]

        // MARK: Middle East
        genres += [
            g("arabicPop", "Arabic pop", region: .middleEast, family: "Pop", tempo: 88...128, peak: 108, groove: .popRock, GenreOpts(sync: 0.28...0.58, m7: 0.22)),
            g("maqam", "Maqam / tarab", region: .middleEast, family: "Classical", tempo: 56...108, peak: 84, groove: .softPulse, GenreOpts(sync: 0.22...0.52, ext: 0.25)),
            g("turkishPop", "Turkish pop", region: .middleEast, family: "Pop", tempo: 92...128, peak: 112, groove: .popRock, GenreOpts(sync: 0.25...0.55)),
        ]

        // MARK: South Asia
        genres += [
            g("bhangra", "Bhangra", region: .southAsia, family: "Punjab", tempo: 100...140, peak: 120, groove: .merengue, GenreOpts(sync: 0.32...0.62)),
            g("bollywood", "Bollywood / filmi", region: .southAsia, family: "India", tempo: 88...140, peak: 112, groove: .popRock, GenreOpts(sync: 0.28...0.58, ext: 0.22)),
            g("qawwali", "Qawwali", region: .southAsia, family: "Sufi", tempo: 72...108, peak: 88, groove: .softPulse, GenreOpts(sync: 0.25...0.52)),
            g("carnatic", "Carnatic", region: .southAsia, family: "Classical", tempo: 80...160, peak: 120, groove: .jazzSwing, GenreOpts(sync: 0.3...0.65, complexity: 2...5, ext: 0.35)),
        ]

        // MARK: East Asia
        genres += [
            g("kPop", "K-pop", region: .eastAsia, family: "Pop", tempo: 100...132, peak: 118, groove: .popRock, GenreOpts(sync: 0.15...0.45, triad: 0.38)),
            g("jPop", "J-pop", region: .eastAsia, family: "Pop", tempo: 96...140, peak: 120, groove: .popRock, GenreOpts(sync: 0.15...0.42, triad: 0.38)),
            g("enka", "Enka", region: .eastAsia, family: "Japan", tempo: 56...88, peak: 72, groove: .bolero, GenreOpts(sync: 0.1...0.35)),
            g("chineseFolk", "Chinese folk", region: .eastAsia, family: "China", tempo: 72...128, peak: 96, groove: .softPulse, GenreOpts(sync: 0.2...0.5)),
        ]

        // MARK: Oceania & Pacific
        genres += [
            g("reggaePacific", "Pacific reggae", region: .oceaniaPacific, family: "Pacific", tempo: 72...98, peak: 84, groove: .reggaeOneDrop, GenreOpts(sync: 0.32...0.6, m7: 0.28)),
            g("hawaiian", "Hawaiian", region: .oceaniaPacific, family: "Pacific", tempo: 72...108, peak: 92, groove: .softPulse, GenreOpts(sync: 0.2...0.48, maj7: 0.28)),
            g("australianRock", "Australian rock", region: .oceaniaPacific, family: "Rock", tempo: 100...150, peak: 124, groove: .rockDrive, GenreOpts(sync: 0.1...0.42, power: 0.35)),
        ]

        // MARK: Classical & art
        genres += [
            g("classical", "Classical", region: .classicalArt, family: "Western classical", tempo: 48...160, peak: 96, groove: .brushWaltz, GenreOpts(sync: 0.1...0.45, complexity: 2...5, ext: 0.35, waltz: 0.15)),
            g("baroque", "Baroque", region: .classicalArt, family: "Western classical", tempo: 72...140, peak: 108, groove: .brushWaltz, GenreOpts(sync: 0.15...0.42, complexity: 2...5, ext: 0.3)),
            g("romantic", "Romantic", region: .classicalArt, family: "Western classical", tempo: 56...120, peak: 84, groove: .softPulse, GenreOpts(sync: 0.12...0.4, complexity: 2...5, ext: 0.32)),
            g("minimalist", "Minimalist", region: .classicalArt, family: "Contemporary", tempo: 72...120, peak: 96, groove: .softPulse, GenreOpts(sync: 0.1...0.38, change: 0...8)),
            g("opera", "Opera", region: .classicalArt, family: "Vocal", tempo: 48...120, peak: 80, groove: .softPulse, GenreOpts(sync: 0.1...0.4, complexity: 2...5, ext: 0.35)),
        ]

        return genres
    }
}
