// SoundLabelCatalog.swift
// =============================================================================
// PRIVACY BANNER — NO NETWORKING IN THE AUDIO PATH.
// Static lookup tables only. No I/O.
// =============================================================================
//
// Maps raw classifier label strings (YAMNet-class, 521 labels) onto the app's
// coarse `SoundCategory` and a speech flag, using keyword matching so it works
// across the full label set without enumerating all 521 entries. The Feature-5
// danger-tier mapping is layered separately on top of this.

import Foundation

enum SoundLabelCatalog {

    /// Keyword → category, checked in priority order (first match wins). Order
    /// matters: e.g. "smoke alarm" must resolve to `.alarm` before "smoke"
    /// could drift elsewhere.
    private static let rules: [(keywords: [String], category: SoundCategory)] = [
        (["smoke detector", "smoke alarm", "carbon monoxide", "fire alarm",
          "alarm", "siren", "buzzer", "smoke"],                     .alarm),
        (["glass", "shatter", "smash", "breaking", "crash", "bang",
          "thud", "clank", "clatter", "explosion", "gunshot"],      .impact),
        (["doorbell", "ding-dong", "knock", "telephone", "ringtone",
          "ring", "beep", "bleep", "alarm clock", "chime"],         .alert),
        (["water", "tap", "faucet", "sink", "shower", "splash",
          "stream", "drip", "pour"],                                .water),
        (["baby", "infant", "cry", "dog", "bark", "cat", "meow",
          "bird", "animal", "purr", "growl"],                       .animal),
        (["car", "horn", "honking", "engine", "traffic", "vehicle",
          "truck", "motorcycle", "bus", "train"],                   .vehicle),
        (["speech", "conversation", "narration", "talk", "shout",
          "yell", "scream", "whisper", "singing", "chatter"],       .speech),
        (["music", "instrument", "guitar", "piano", "drum",
          "melody", "song"],                                        .ambient),
    ]

    /// Labels that represent human vocalisation (gates transcription).
    private static let speechKeywords = [
        "speech", "conversation", "narration", "talk", "shout",
        "yell", "scream", "whisper", "chatter"
    ]

    static func category(for label: String) -> SoundCategory {
        let lower = label.lowercased()
        for rule in rules where rule.keywords.contains(where: { lower.contains($0) }) {
            return rule.category
        }
        return .other
    }

    static func isSpeech(_ label: String) -> Bool {
        let lower = label.lowercased()
        return speechKeywords.contains { lower.contains($0) }
    }
}
