import Foundation
import AVFoundation
import SphereCore

public struct SpeechVoice: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let language: String
    public let quality: Int

    public init(id: String, name: String, language: String, quality: Int) {
        self.id = id
        self.name = name
        self.language = language
        self.quality = quality
    }

    public var label: String {
        "\(name) — \(language)"
    }

    public var isEnhanced: Bool {
        quality >= AVSpeechSynthesisVoiceQuality.enhanced.rawValue
    }
}

/// Native text-to-speech via AVFoundation. This is the same engine behind
/// `/usr/bin/say`, but with runtime control of voice, rate, pause and resume.
@MainActor
public final class SpeechService: NSObject {
    private let synthesizer = AVSpeechSynthesizer()

    /// Called on the main actor whenever the speaking state may have changed.
    public var onSpeakingChanged: ((Bool, Bool) -> Void)?

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    public var isSpeaking: Bool { synthesizer.isSpeaking }
    public var isPaused: Bool { synthesizer.isPaused }

    nonisolated public static func availableVoices() -> [SpeechVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .map {
                SpeechVoice(
                    id: $0.identifier,
                    name: $0.name,
                    language: $0.language,
                    quality: $0.quality.rawValue
                )
            }
            .sorted {
                if $0.language == $1.language {
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return $0.language < $1.language
            }
    }

    public func speak(
        _ text: String,
        voiceIdentifier: String?,
        rate: Double = 0.5,
        pitch: Double = 1.0,
        volume: Double = 1.0
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        if let voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        } else {
            let preferred = Locale.preferredLanguages.first ?? "en-US"
            utterance.voice = AVSpeechSynthesisVoice(language: preferred)
                ?? AVSpeechSynthesisVoice(language: "en-US")
        }
        utterance.rate = Float(max(0.0, min(1.0, rate)))
        utterance.pitchMultiplier = Float(pitch)
        utterance.volume = Float(volume)

        SphereLog.app.write("speech", "speak \(trimmed.count) chars voice=\(utterance.voice?.identifier ?? "default") rate=\(rate)")
        synthesizer.speak(utterance)
        notify()
    }

    public func stop() {
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        notify()
    }

    public func pause() {
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
        }
        notify()
    }

    public func resume() {
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
        }
        notify()
    }

    private func notify() {
        onSpeakingChanged?(synthesizer.isSpeaking, synthesizer.isPaused)
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.notify() }
    }

    nonisolated public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.notify() }
    }

    nonisolated public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.notify() }
    }

    nonisolated public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didPause utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.notify() }
    }

    nonisolated public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didContinue utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.notify() }
    }
}
