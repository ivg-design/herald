import AVFoundation
import Speech

/// AAC m4a, mono, 32 kbps (about 240 KB a minute). Written with AVAudioRecorder; nothing starts until `start`.
@MainActor
final class MicRecorder: AudioRecording {
    private var recorder: AVAudioRecorder?

    func start(to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 22_050,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let r = try AVAudioRecorder(url: url, settings: settings)
        guard r.prepareToRecord(), r.record() else {
            throw NSError(domain: "Herald.VoiceReply", code: 1, userInfo: [NSLocalizedDescriptionKey: "the microphone could not be opened"])
        }
        recorder = r
    }

    func stop() -> Double {
        guard let r = recorder else { return 0 }
        let t = r.currentTime
        r.stop()
        recorder = nil
        return t
    }

    func cancel() { recorder?.stop(); recorder?.deleteRecording(); recorder = nil }

    /// Asks once; the system remembers the answer. This is the only place that triggers the microphone prompt.
    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }
}

/// On-device transcription: `requiresOnDeviceRecognition = true`, so audio never leaves the Mac for this. When the language model
/// is not installed or Speech access is off there is no transcript, and the sender gets the audio alone.
struct OnDeviceTranscriber: Transcribing {
    func transcribe(_ url: URL) async -> String? {
        let status = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard status == .authorized, let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { return nil }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        return await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let result, result.isFinal { finished = true; c.resume(returning: result.bestTranscription.formattedString); return }
                if error != nil { finished = true; c.resume(returning: nil) }
            }
        }
    }
}
