// TranscriptionLine.swift
// Single line of transcribed speech with metadata and keyword highlighting.

import Foundation
import SwiftUI

struct TranscriptionLine: Identifiable, Equatable {
    let id: UUID
    let text: String
    let confidence: Float
    var keywords: [String]
    let timestamp: Date
    var direction: SoundDirection?
    /// Snapshot of the live microphone spectrum when the line was captured,
    /// used to draw the volume waveform in caption bubbles.
    var levels: [Float]

    init(text: String,
         confidence: Float,
         keywords: [String] = [],
         direction: SoundDirection? = nil,
         levels: [Float] = [],
         timestamp: Date = Date()) {
        self.id = UUID()
        self.text = text
        self.confidence = confidence
        self.keywords = keywords
        self.direction = direction
        self.levels = levels
        self.timestamp = timestamp
    }

    var containsKeyword: Bool { !keywords.isEmpty }

    /// Returns text with keywords highlighted using AttributedString attributes.
    var attributedText: AttributedString {
        var attributed = AttributedString(text)
        attributed.foregroundColor = Color(red: 0.99, green: 0.77, blue: 0.69).opacity(0.82)

        let lowerText = text.lowercased()
        for keyword in keywords {
            let lowerKeyword = keyword.lowercased()
            var searchRange = lowerText.startIndex..<lowerText.endIndex
            while let foundRange = lowerText.range(of: lowerKeyword, range: searchRange) {
                if let attributedRange = Range(foundRange, in: attributed) {
                    attributed[attributedRange].foregroundColor = Color(red: 0.91, green: 0.39, blue: 0.10)
                    attributed[attributedRange].font = .system(size: 15, weight: .semibold)
                }
                searchRange = foundRange.upperBound..<lowerText.endIndex
            }
        }
        return attributed
    }
}
