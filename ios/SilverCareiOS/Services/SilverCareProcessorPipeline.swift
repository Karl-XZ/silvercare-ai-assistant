import Foundation
import SilverCareCore

actor SilverCareProcessorPipeline {
    private let processor: SilverCareProcessor

    init(client: SilverCareAIClient) {
        processor = SilverCareProcessor(client: client)
    }

    func processFrame(_ imageDataURL: String) throws -> [SilverCareMessage] {
        try processor.processFrame(imageDataURL)
    }

    func processInquiry(imageDataURL: String, audioDataURL: String) throws -> [SilverCareMessage] {
        try processor.processInquiry(imageDataURL: imageDataURL, audioDataURL: audioDataURL)
    }

    func processTextInquiry(imageDataURL: String, transcript: String) throws -> [SilverCareMessage] {
        try processor.processTextInquiry(imageDataURL: imageDataURL, transcript: transcript)
    }
}
