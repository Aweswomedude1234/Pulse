// PulseAudioInterruption.swift
// =============================================================================
// Audio interruptions, expressed once for both platforms.
//
// On iOS an interruption is a first-class audio-session event: a call comes in,
// Siri activates, another app takes the mic, and the system tells us. macOS has
// no audio session and therefore no such notification — the closest equivalent
// is AVAudioEngine reporting that its configuration changed underneath it
// (input device unplugged, default input switched).
//
// Callers subscribe to `notificationName` and decode with `type(of:)` rather
// than reaching for AVAudioSession directly.
// =============================================================================

import Foundation
import AVFoundation

enum PulseAudioInterruption {

    /// What happened to our access to the microphone.
    enum Kind {
        /// Capture has stopped and will not resume on its own.
        case began
        /// The interrupting event finished; capture may be restarted.
        case ended
    }

    /// The notification to observe for interruptions on this platform.
    static var notificationName: Notification.Name {
        #if os(iOS)
        return AVAudioSession.interruptionNotification
        #else
        return .AVAudioEngineConfigurationChange
        #endif
    }

    /// Decodes an observed notification, or nil if it carries no usable type.
    static func type(of note: Notification) -> Kind? {
        #if os(iOS)
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return nil }
        switch type {
        case .began:  return .began
        case .ended:  return .ended
        @unknown default: return nil
        }
        #else
        // A configuration change means the graph we were capturing through is
        // no longer valid — from the caller's point of view capture has stopped.
        return .began
        #endif
    }
}
