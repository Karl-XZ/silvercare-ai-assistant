import AVFoundation
import Foundation

final class PCM16AudioRecorderService {
    enum RecorderError: Error, LocalizedError {
        case alreadyRecording
        case notRecording
        case notAuthorized
        case conversionUnavailable
        case tooShort

        var errorDescription: String? {
            switch self {
            case .alreadyRecording:
                return "语音识别正在进行中。"
            case .notRecording:
                return "没有正在进行的录音。"
            case .notAuthorized:
                return "请在系统设置中允许麦克风权限。"
            case .conversionUnavailable:
                return "当前设备无法转换 16kHz 单声道录音。"
            case .tooShort:
                return "录音太短，请按住说完整问题。"
            }
        }
    }

    private let audioEngine = AVAudioEngine()
    private let lock = NSLock()
    private var pcm = Data()
    private var converter: AVAudioConverter?
    private let targetSampleRate: Double = 16_000
    private let targetChannels: AVAudioChannelCount = 1
    private let minimumPCMBytes = 1_600

    var isRecording: Bool {
        audioEngine.isRunning
    }

    func start() throws {
        guard !audioEngine.isRunning else { throw RecorderError.alreadyRecording }

        lock.lock()
        pcm.removeAll(keepingCapacity: true)
        lock.unlock()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try? session.setPreferredSampleRate(targetSampleRate)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: targetSampleRate,
                channels: targetChannels,
                interleaved: true
            ),
            let audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat)
        else {
            throw RecorderError.conversionUnavailable
        }
        converter = audioConverter

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.appendConverted(buffer: buffer, targetFormat: targetFormat)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    func stopPCM() throws -> Data {
        guard audioEngine.isRunning else { throw RecorderError.notRecording }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        converter = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        lock.lock()
        let data = pcm
        pcm.removeAll(keepingCapacity: true)
        lock.unlock()

        guard data.count >= minimumPCMBytes else { throw RecorderError.tooShort }
        return data
    }

    func stopDataURL() throws -> String {
        let data = try stopPCM()
        let wav = Self.wavBytes(pcm: data, sampleRate: Int(targetSampleRate), channels: Int(targetChannels), bitsPerSample: 16)
        return "data:audio/wav;base64,\(wav.base64EncodedString())"
    }

    func cancel() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        converter = nil
        lock.lock()
        pcm.removeAll(keepingCapacity: true)
        lock.unlock()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func appendConverted(buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(max(1, ceil(Double(buffer.frameLength) * ratio) + 16))
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var conversionError: NSError?
        var sourceProvided = false
        converter.convert(to: converted, error: &conversionError) { _, status in
            if sourceProvided {
                status.pointee = .noDataNow
                return nil
            }
            sourceProvided = true
            status.pointee = .haveData
            return buffer
        }
        guard conversionError == nil else { return }

        let audioBuffer = converted.audioBufferList.pointee.mBuffers
        guard let bytes = audioBuffer.mData, audioBuffer.mDataByteSize > 0 else { return }
        lock.lock()
        pcm.append(bytes.assumingMemoryBound(to: UInt8.self), count: Int(audioBuffer.mDataByteSize))
        lock.unlock()
    }

    private static func wavBytes(pcm: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        var data = Data(capacity: 44 + pcm.count)
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46])
        data.appendLittleEndian(UInt32(36 + pcm.count))
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45])
        data.append(contentsOf: [0x66, 0x6d, 0x74, 0x20])
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(channels))
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(sampleRate * channels * bitsPerSample / 8))
        data.appendLittleEndian(UInt16(channels * bitsPerSample / 8))
        data.appendLittleEndian(UInt16(bitsPerSample))
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61])
        data.appendLittleEndian(UInt32(pcm.count))
        data.append(pcm)
        return data
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
