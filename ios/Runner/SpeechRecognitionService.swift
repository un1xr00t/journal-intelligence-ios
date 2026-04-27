import AVFoundation
import Flutter
import Foundation
import Speech

final class SpeechRecognitionService: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var audioEngine = AVAudioEngine()
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var recognizer = SFSpeechRecognizer(locale: Locale.current)

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    emit(status: "idle", transcript: nil, isListening: false, isFinal: false, error: nil)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  func start(result: @escaping FlutterResult) {
    requestPermissions { [weak self] permissionError in
      guard let self else {
        result(
          FlutterError(
            code: "voice_unavailable",
            message: "Voice capture is unavailable.",
            details: nil
          )
        )
        return
      }

      if let permissionError {
        result(permissionError)
        return
      }

      DispatchQueue.main.async {
        do {
          try self.startRecognition()
          result(nil)
        } catch {
          let flutterError = FlutterError(
            code: "voice_start_failed",
            message: error.localizedDescription,
            details: nil
          )
          self.emit(
            status: "error",
            transcript: nil,
            isListening: false,
            isFinal: false,
            error: error.localizedDescription
          )
          result(flutterError)
        }
      }
    }
  }

  func stop() {
    audioEngine.stop()
    recognitionRequest?.endAudio()
    emit(status: "stopped", transcript: nil, isListening: false, isFinal: true, error: nil)
  }

  func cancel() {
    recognitionTask?.cancel()
    stopRecognition()
    emit(status: "cancelled", transcript: nil, isListening: false, isFinal: true, error: nil)
  }

  private func requestPermissions(completion: @escaping (FlutterError?) -> Void) {
    SFSpeechRecognizer.requestAuthorization { authStatus in
      guard authStatus == .authorized else {
        completion(
          FlutterError(
            code: "speech_permission_denied",
            message: "Speech recognition permission was denied.",
            details: nil
          )
        )
        return
      }

      AVAudioSession.sharedInstance().requestRecordPermission { granted in
        if granted {
          completion(nil)
        } else {
          completion(
            FlutterError(
              code: "microphone_permission_denied",
              message: "Microphone permission was denied.",
              details: nil
            )
          )
        }
      }
    }
  }

  private func startRecognition() throws {
    cancel()

    recognizer = SFSpeechRecognizer(locale: Locale.current)
    guard let recognizer, recognizer.isAvailable else {
      throw NSError(
        domain: "SpeechRecognitionService",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Speech recognition is unavailable for the current device language."]
      )
    }

    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.record, mode: .measurement, options: .duckOthers)
    try session.setActive(true, options: .notifyOthersOnDeactivation)

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    recognitionRequest = request

    let inputNode = audioEngine.inputNode
    let format = inputNode.outputFormat(forBus: 0)
    inputNode.removeTap(onBus: 0)
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
      self?.recognitionRequest?.append(buffer)
    }

    audioEngine.prepare()
    try audioEngine.start()

    recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
      guard let self else { return }

      if let result {
        let text = result.bestTranscription.formattedString
        self.emit(
          status: result.isFinal ? "final" : "listening",
          transcript: text,
          isListening: !result.isFinal,
          isFinal: result.isFinal,
          error: nil
        )
        if result.isFinal {
          self.stopRecognition()
        }
      }

      if let error {
        self.stopRecognition()
        self.emit(
          status: "error",
          transcript: nil,
          isListening: false,
          isFinal: true,
          error: error.localizedDescription
        )
      }
    }

    emit(status: "listening", transcript: nil, isListening: true, isFinal: false, error: nil)
  }

  private func stopRecognition() {
    audioEngine.stop()
    audioEngine.inputNode.removeTap(onBus: 0)
    recognitionRequest?.endAudio()
    recognitionRequest = nil
    recognitionTask?.cancel()
    recognitionTask = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func emit(
    status: String,
    transcript: String?,
    isListening: Bool,
    isFinal: Bool,
    error: String?
  ) {
    guard let eventSink else { return }
    eventSink([
      "status": status,
      "transcript": transcript as Any,
      "isListening": isListening,
      "isFinal": isFinal,
      "error": error as Any,
    ])
  }
}
