import XCTest
@testable import OpenGlasses

/// Plan JM P2 — the OpenAI transcription upload: a WAV of the question, the model, the vocabulary
/// as a bounded prompt, the API key as a bearer token.
final class OpenAIDictationRequestTests: XCTestCase {

    private let boundary = "test-boundary-1234"

    func testTheRequestGoesToTheTranscriptionEndpointWithTheAPIKey() {
        let request = OpenAIDictationRequest.make(wav: Data([1, 2, 3]), apiKey: "sk-test-invented",
                                                  vocabulary: [], boundary: boundary)
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test-invented")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"),
                       "multipart/form-data; boundary=\(boundary)")
        XCTAssertGreaterThan(request.timeoutInterval, 0)
    }

    func testTheBodyCarriesTheModelThePromptAndTheFile() throws {
        let wav = OpenAIDictationRequest.wav(samples: [0, 0.5, -0.5], sampleRate: 16_000)
        let request = OpenAIDictationRequest.make(wav: wav, apiKey: "k", vocabulary: ["XR-7720", "R-454B"],
                                                  boundary: boundary)
        let body = try XCTUnwrap(request.httpBody)
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("--\(boundary)\r\n"))
        XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"model\"\r\n\r\ngpt-4o-transcribe\r\n"))
        XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"prompt\"\r\n\r\nXR-7720, R-454B\r\n"))
        XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"response_format\"\r\n\r\njson\r\n"))
        XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"file\"; filename=\"question.wav\"\r\nContent-Type: audio/wav\r\n\r\n"))
        XCTAssertTrue(text.hasSuffix("--\(boundary)--\r\n"))
        XCTAssertNotNil(body.range(of: wav), "the WAV is carried byte for byte")
    }

    func testNoVocabularyMeansNoPromptField() {
        let names = OpenAIDictationRequest.fields(vocabulary: []).map(\.name)
        XCTAssertEqual(names, ["model", "response_format"])
    }

    func testThePromptIsWholeTermsWithinTheBound() {
        let terms = (0..<500).map { "TERM-\($0)" }
        let prompt = OpenAIDictationRequest.prompt(from: ["  first ", "FIRST"] + terms)
        XCTAssertLessThanOrEqual(prompt.count, OpenAIDictationRequest.maxPromptCharacters)
        XCTAssertTrue(prompt.hasPrefix("first, TERM-0, TERM-1"), "trimmed, de-duplicated, in order")
        XCTAssertFalse(prompt.hasSuffix(","))
        for piece in prompt.components(separatedBy: ", ").dropFirst() {
            XCTAssertTrue(piece.hasPrefix("TERM-"), "never a cut term: \(piece)")
        }
    }

    func testTheWAVHeaderDescribes16BitMono() throws {
        let samples: [Float] = [0, 1, -1, 0.5]
        let wav = OpenAIDictationRequest.wav(samples: samples, sampleRate: 16_000)
        XCTAssertEqual(wav.count, 44 + samples.count * 2)
        XCTAssertEqual(String(decoding: wav[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: wav[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(String(decoding: wav[12..<16], as: UTF8.self), "fmt ")
        XCTAssertEqual(String(decoding: wav[36..<40], as: UTF8.self), "data")

        func u16(_ offset: Int) -> UInt16 { UInt16(wav[offset]) | UInt16(wav[offset + 1]) << 8 }
        func u32(_ offset: Int) -> UInt32 {
            (0..<4).reduce(UInt32(0)) { $0 | UInt32(wav[offset + $1]) << (8 * UInt32($1)) }
        }
        XCTAssertEqual(u32(4), UInt32(36 + samples.count * 2), "RIFF size")
        XCTAssertEqual(u16(20), 1, "PCM")
        XCTAssertEqual(u16(22), 1, "mono")
        XCTAssertEqual(u32(24), 16_000, "sample rate")
        XCTAssertEqual(u32(28), 32_000, "byte rate")
        XCTAssertEqual(u16(32), 2, "block align")
        XCTAssertEqual(u16(34), 16, "bits per sample")
        XCTAssertEqual(u32(40), UInt32(samples.count * 2), "data size")
        XCTAssertEqual(wav.subdata(in: 44..<wav.count), PCMConverter.linear16(fromMono: samples))
    }

    func testTheTranscriptIsReadFromTheJSONReply() {
        XCTAssertEqual(OpenAIDictationRequest.transcript(from: Data(#"{"text":"  Check the TXV. "}"#.utf8)),
                       "Check the TXV.")
        XCTAssertNil(OpenAIDictationRequest.transcript(from: Data("not json".utf8)))
        XCTAssertNil(OpenAIDictationRequest.transcript(from: Data(#"{"error":{}}"#.utf8)))
    }
}
