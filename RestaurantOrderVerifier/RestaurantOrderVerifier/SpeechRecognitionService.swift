import Speech

class SpeechRecognitionService: NSObject, SFSpeechRecognizerDelegate {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    override init() {
        super.init()
        speechRecognizer.delegate = self
    }
    
    func startRecording(
        textUpdateHandler: @escaping (String) -> Void,
        itemsCompletion: @escaping (String) -> Void,
        errorHandler: @escaping (Error) -> Void
    ) {
        // Request authorization
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    do {
                        try self.startRecordingSession(
                            textUpdateHandler: textUpdateHandler,
                            itemsCompletion: itemsCompletion,
                            errorHandler: errorHandler
                        )
                    } catch {
                        errorHandler(error)
                    }
                case .denied:
                    errorHandler(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Speech recognition permission denied"]))
                case .restricted:
                    errorHandler(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Speech recognition not available on this device"]))
                case .notDetermined:
                    errorHandler(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Speech recognition not yet authorized"]))
                @unknown default:
                    errorHandler(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown speech recognition authorization status"]))
                }
            }
        }
    }
    
    private func startRecordingSession(
        textUpdateHandler: @escaping (String) -> Void,
        itemsCompletion: @escaping (String) -> Void,
        errorHandler: @escaping (Error) -> Void
    ) throws {
        // Cancel any ongoing task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to create recognition request"])
        }
        recognitionRequest.shouldReportPartialResults = true
        
        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            if let error = error {
                errorHandler(error)
                return
            }
            
            if let result = result {
                let text = result.bestTranscription.formattedString
                textUpdateHandler(text)
                
                if result.isFinal {
                    itemsCompletion(text)
                    self?.stopRecording()
                }
            }
        }
        
        // Configure audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
    }
    
    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }
}
