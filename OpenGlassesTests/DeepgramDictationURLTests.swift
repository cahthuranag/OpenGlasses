import XCTest
@testable import OpenGlasses

/// Plan JM P2 — what the Deepgram dictation socket's URL carries off the phone: one speaker, no
/// diarisation, interim results, smart formatting, endpointing, and the P0 vocabulary as keyterms.
final class DeepgramDictationURLTests: XCTestCase {

    private func items(_ url: URL?) -> [URLQueryItem] {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [] }
        return components.queryItems ?? []
    }

    private func value(_ name: String, in url: URL?) -> String? {
        items(url).first { $0.name == name }?.value
    }

    func testDictationIsNotDiarizedAndStreamsInterims() {
        let url = DeepgramDictationRequest.url(sampleRate: 48_000, model: "nova-3", vocabulary: [])
        XCTAssertEqual(url?.scheme, "wss")
        XCTAssertEqual(url?.host, "api.deepgram.com")
        XCTAssertEqual(url?.path, "/v1/listen")
        XCTAssertEqual(value("diarize", in: url), "false")
        XCTAssertEqual(value("interim_results", in: url), "true")
        XCTAssertEqual(value("smart_format", in: url), "true")
        XCTAssertEqual(value("encoding", in: url), "linear16")
        XCTAssertEqual(value("sample_rate", in: url), "48000")
        XCTAssertEqual(value("channels", in: url), "1")
        XCTAssertEqual(value("model", in: url), "nova-3")
        XCTAssertNotNil(value("endpointing", in: url))
        XCTAssertFalse(items(url).contains { $0.name == "keyterm" }, "no vocabulary, no keyterms")
    }

    func testTheVocabularyRidesAsRepeatedKeyterms() {
        let url = DeepgramDictationRequest.url(sampleRate: 16_000, model: "nova-3",
                                               vocabulary: ["XR-7720", "R-454B", "condenser fan motor"])
        let keyterms = items(url).filter { $0.name == "keyterm" }.compactMap(\.value)
        XCTAssertEqual(keyterms, ["XR-7720", "R-454B", "condenser fan motor"])
    }

    func testKeytermsAreEncodedSoNothingIsMisread() throws {
        let url = try XCTUnwrap(DeepgramDictationRequest.url(sampleRate: 16_000, model: "nova-3",
                                                             vocabulary: ["A&B + C=D", "3/4\" pipe"]))
        let query = try XCTUnwrap(url.query(percentEncoded: true))
        XCTAssertTrue(query.contains("keyterm=A%26B%20%2B%20C%3DD"), query)
        XCTAssertTrue(query.contains("keyterm=3%2F4%22%20pipe"), query)
        XCTAssertFalse(query.contains("+"), "a literal + reads as a space on the server")
        let decoded = items(url).filter { $0.name == "keyterm" }.compactMap(\.value)
        XCTAssertEqual(decoded, ["A&B + C=D", "3/4\" pipe"], "round-trips exactly")
    }

    func testKeytermsAreTrimmedDeduplicatedAndCapped() {
        let many = (0..<200).map { "MODEL-\($0)" }
        let terms = DeepgramDictationRequest.keyterms(from: ["  R-410A ", "r-410a", ""] + many)
        XCTAssertEqual(terms.first, "R-410A")
        XCTAssertEqual(terms.filter { $0.lowercased() == "r-410a" }.count, 1)
        XCTAssertEqual(terms.count, DeepgramDictationRequest.maxKeyterms)
        XCTAssertEqual(terms[1], "MODEL-0", "the cap keeps the vocabulary's own order and trims its end")
    }

    func testOverlongTermsAreDropped() {
        let long = String(repeating: "x", count: DeepgramDictationRequest.maxKeytermLength + 1)
        XCTAssertEqual(DeepgramDictationRequest.keyterms(from: [long, "TXV"]), ["TXV"])
    }

    func testOnlyNova3TakesKeyterms() {
        let url = DeepgramDictationRequest.url(sampleRate: 16_000, model: "nova-2", vocabulary: ["R-32"])
        XCTAssertFalse(items(url).contains { $0.name == "keyterm" },
                       "keyterm prompting is a Nova-3 feature; another model gets none rather than a refusal")
        XCTAssertEqual(value("model", in: url), "nova-2")
    }

    func testTheCaptionsURLIsUntouched() {
        // Captions keep their own diarized URL; the dictation builder is separate.
        let captions = Config.deepgramStreamingURL(sampleRate: 16_000)
        XCTAssertEqual(value("diarize", in: captions), "true")
    }
}
