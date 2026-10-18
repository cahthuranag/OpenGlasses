import XCTest
@testable import OpenGlasses

/// A tester's job 1028: "page 34 of the service manual", asked twice, opened the Installation
/// Instructions' page 34 both times — both manuals have a page 34, and the tool took the first.
final class ManualDocumentChoiceTests: XCTestCase {

    private let install = "SLP99UHVK Installation Instructions"
    private let service = "SLP99UHVK Service Manual"

    private func passage(_ name: String, page: Int = 34) -> DocumentStore.Passage {
        DocumentStore.Passage(documentId: name, documentName: name, chunkIndex: 0, text: "…",
                              similarity: 0, page: page, section: nil, kind: .prose, figure: nil)
    }

    private var bothPage34: [DocumentStore.Passage] { [passage(install), passage(service)] }

    func testTheTechniciansWordsChooseTheManual() {
        XCTAssertEqual(ManualDocumentChoice.pick(bothPage34, document: nil,
                                                 said: "Hey check page 34 of the service manual item number two"),
                       .found(passage(service)))
        XCTAssertEqual(ManualDocumentChoice.pick(bothPage34, document: nil,
                                                 said: "open page 34 in the installation instructions"),
                       .found(passage(install)))
    }

    func testTheCallsDocumentChoosesTheManual() {
        XCTAssertEqual(ManualDocumentChoice.pick(bothPage34, document: "service manual", said: nil),
                       .found(passage(service)))
        XCTAssertEqual(ManualDocumentChoice.pick(bothPage34, document: "SM", said: nil),
                       .found(passage(service)), "the vault's own initials")
        XCTAssertEqual(ManualDocumentChoice.pick(bothPage34, document: "II", said: nil),
                       .found(passage(install)))
    }

    func testAPageInSeveralManualsWithNoBookNamedIsAskedNotGuessed() {
        guard case .problem(let sentence) = ManualDocumentChoice.pick(bothPage34, document: nil,
                                                                      said: "show me page 34") else {
            return XCTFail("two books and no name is a question")
        }
        XCTAssertTrue(sentence.contains(install) && sentence.contains(service), sentence)
        XCTAssertTrue(sentence.contains("Nothing was opened"), sentence)
    }

    func testAPageInOneManualNeedsNoName() {
        XCTAssertEqual(ManualDocumentChoice.pick([passage(service, page: 80)], document: nil, said: nil),
                       .found(passage(service, page: 80)))
    }

    func testANamedManualWithoutThatPageSaysWhereItIs() {
        guard case .problem(let sentence) = ManualDocumentChoice.pick([passage(install)],
                                                                      document: "service manual", said: nil) else {
            return XCTFail("the named book does not have it")
        }
        XCTAssertTrue(sentence.contains(install), sentence)
    }

    func testTheWordManualAloneNamesNoBook() {
        XCTAssertNil(ManualDocumentChoice.named(in: "what does the manual say on page 34",
                                                among: [install, service]))
    }
}
