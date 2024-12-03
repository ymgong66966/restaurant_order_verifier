import AVFoundation

class SpeechRecognitionService: NSObject {
    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var isRecording = false
    private let serverURL = "http://127.0.0.1:5001/transcribe_audio_chunk"
    private var converter: AVAudioConverter?
    private var monoFormat: AVAudioFormat?
    private var audioData = Data()
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement)
            try session.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }
    
    func startRecording(
        textUpdateHandler: @escaping (String) -> Void,
        itemsCompletion: @escaping (String) -> Void,
        errorHandler: @escaping (Error) -> Void
    ) {
        guard !isRecording else { return }
        
        // Reset audio data
        audioData = Data()
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("Input format: \(inputFormat)")
        
        do {
            // Create mono format for conversion
            monoFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: inputFormat.sampleRate,
                channels: 1,
                interleaved: true
            )
            
            guard let monoFormat = monoFormat else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create mono format"])
            }
            
            converter = AVAudioConverter(from: inputFormat, to: monoFormat)
            
            guard let converter = converter else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create converter"])
            }
            
            // Install tap with input format
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] (buffer, _) in
                guard let self = self,
                      let monoFormat = self.monoFormat,
                      let converter = self.converter else { return }
                
                let frameCount = AVAudioFrameCount(buffer.frameLength)
                guard let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: monoFormat,
                    frameCapacity: frameCount
                ) else { return }
                
                var error: NSError?
                converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }
                
                if let error = error {
                    print("Conversion error: \(error)")
                    return
                }
                
                // Append converted buffer data to our audio data
                if let channelData = convertedBuffer.int16ChannelData {
                    let channelDataPtr = channelData[0]
                    let channelDataSize = Int(convertedBuffer.frameLength * convertedBuffer.format.streamDescription.pointee.mBytesPerFrame)
                    let channelDataBuffer = UnsafeBufferPointer(start: channelDataPtr, count: channelDataSize / 2)
                    let data = Data(buffer: channelDataBuffer)
                    self.audioData.append(data)
                }
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            textUpdateHandler("Recording started...")
            
        } catch {
            print("Recording setup error: \(error)")
            errorHandler(error)
        }
    }
    
    func stopRecording(completion: @escaping (Result<String, Error>) -> Void) {
        guard isRecording else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not recording"])))
            return
        }
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false
        
        // Create WAV header
        let wavHeader = createWAVHeader(sampleRate: 44100, bitsPerSample: 16, channels: 1, dataSize: UInt32(audioData.count))
        
        // Combine header and audio data
        var wavData = Data()
        wavData.append(wavHeader)
        wavData.append(audioData)
        
        // Send to server
        let base64Audio = wavData.base64EncodedString()
        
        var request = URLRequest(url: URL(string: serverURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let json: [String: Any] = ["audio_data": base64Audio]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let data = data else {
                    completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let text = json["text"] as? String {
                        completion(.success(text))
                    } else {
                        completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])))
                    }
                } catch {
                    completion(.failure(error))
                }
            }.resume()
            
        } catch {
            completion(.failure(error))
        }
    }
    
    private func createWAVHeader(sampleRate: UInt32, bitsPerSample: UInt16, channels: UInt16, dataSize: UInt32) -> Data {
        var header = Data()
        
        // RIFF chunk descriptor
        header.append("RIFF".data(using: .utf8)!)
        header.append(withUnsafeBytes(of: UInt32(dataSize + 36).littleEndian) { Data($0) })
        header.append("WAVE".data(using: .utf8)!)
        
        // "fmt " sub-chunk
        header.append("fmt ".data(using: .utf8)!)
        header.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) }) // Subchunk1Size
        header.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // AudioFormat (1 = PCM)
        header.append(withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: (sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8).littleEndian) { Data($0) }) // ByteRate
        header.append(withUnsafeBytes(of: (channels * bitsPerSample / 8).littleEndian) { Data($0) }) // BlockAlign
        header.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        
        // "data" sub-chunk
        header.append("data".data(using: .utf8)!)
        header.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        
        return header
    }
}
