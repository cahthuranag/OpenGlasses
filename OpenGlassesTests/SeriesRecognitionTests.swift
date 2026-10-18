import XCTest
@testable import OpenGlasses

/// A tester's `SLP99UH090XV36BK` on a vault written for the whole SLP99UH series: no one listed
/// size claimed it (it is two edits from both `…090XV36CK` and `…070XV36BK`), so every answer for
/// the rest of the job called the furnace unlisted and the manuals unconfirmed for it.
///
/// Pure, over an inline copy of the example vault's model headings — CI does not carry the vault.
final class SeriesRecognitionTests: XCTestCase {

    private static let models = """
    # Models — SLP99UHVK series

    ## SLP99UH070XV36BK (070XV36B, SLP99UHXV-070-36B, SLP99UH070V36BK; size code A; B cabinet 17-1/2 in. wide)
    ## SLP99UH090XV36CK (090XV36C, SLP99UHXV-090-36C, SLP99UH090V36CK; size code b; C cabinet 21 in. wide)
    ## SLP99UH090XV48CK (090XV48C, SLP99UHXV-090-48C, SLP99UH090V48CK; size code C; C cabinet)
    ## SLP99UH090XV60CK (090XV60C, -090-060C, SLP99UHXV-090-60C, SLP99UH090V60CK; size code d; C cabinet)
    ## SLP99UH110XV60CK (110XV60C, SLP99UHXV-110-60C, SLP99UH110V60CK; size code E; C cabinet)
    ## SLP99UH135XV60DK (135XV60D, SLP99UHXV-135-60D, SLP99UH135V60DK; size code F; D cabinet 24-1/2 in. wide)
    """

    /// The model the tester read out.
    private static let testersModel = "SLP99UH090XV36BK"

    private static let serviceValues = """
    ## R-454B (A2L) refrigerant detection
    ## Flame signal — TABLE 39 II p.64
    """

    private let index = VaultModelIndex(vaultName: "Lennox SLP99 Furnace Service",
                                        files: [("models.md", models), ("service_values.md", serviceValues)])

    func testTheVaultsSeriesIsReadFromItsModelHeadings() {
        XCTAssertEqual(index.seriesStem, "SLP99UH", "a topic heading such as R-454B does not break the series")
    }

    func testTheTestersModelIsASeriesMember() {
        XCTAssertEqual(EquipmentRecognition.resolve(stated: "SLP99UH090XV36BK", index: index),
                       .series(stem: "SLP99UH", file: "models.md"))
        XCTAssertEqual(EquipmentRecognition.resolve(stated: "SLP99UH090XV36B", index: index).kind, .series,
                       "said one letter short")
    }

    func testListedSizesStillResolveToTheirSections() {
        XCTAssertEqual(EquipmentRecognition.resolve(stated: "SLP99UH090XV36CK", index: index).kind, .exact)
        XCTAssertEqual(EquipmentRecognition.resolve(stated: "SLP99UH090XV48C", index: index).kind, .near)
        XCTAssertEqual(EquipmentRecognition.resolve(stated: "070XV36B", index: index).kind, .alias)
    }

    func testAChangedLetterInTheSeriesShapeIsAnotherProduct() {
        XCTAssertEqual(EquipmentRecognition.resolve(stated: "SLP99UH070XB36B", index: index), .unmatched,
                       "every listed model has XV there — Job 1011's XB unit stays out of the vault")
        XCTAssertEqual(EquipmentRecognition.resolve(stated: "SLP99UH09XV36BK", index: index), .unmatched)
        XCTAssertEqual(EquipmentRecognition.resolve(stated: "SLP99UH090XV36BKZZ", index: index), .unmatched)
    }

    func testASeriesMemberIsCoveredAndThePromptStopsCallingItUnlisted() {
        let identity = EquipmentRecognition.identity(
            stated: "SLP99UH090XV36BK", resolution: EquipmentRecognition.resolve(stated: "SLP99UH090XV36BK", index: index),
            source: .spoken, recognisedAt: Date(timeIntervalSince1970: 0))
        XCTAssertFalse(identity.isOutOfVault)
        XCTAssertTrue(identity.isSeriesMember)
        XCTAssertEqual(identity.stated, "SLP99UH090XV36BK")
        XCTAssertEqual(identity.vaultSectionIfDifferent, "SLP99UH series")
        XCTAssertFalse(identity.promptBlock.contains("not a model the loaded manuals cover"), identity.promptBlock)
        XCTAssertTrue(identity.promptBlock.contains("cover the SLP99UH series as a whole"), identity.promptBlock)
        XCTAssertTrue(identity.announcement.contains("covered by the loaded manuals"), identity.announcement)
    }

    func testASeriesMemberIsNotRefusedAsAnotherMachine() {
        let member = Self.testersModel
        XCTAssertTrue(index.isKnown(token: member))
        let question = "the \(member) won't ignite"
        XCTAssertEqual(EquipmentScopeCheck.check(text: question, index: index, active: nil), .inScope)
        guard case .unknownEquipment = EquipmentScopeCheck.check(text: "a Carrier 58MVB90 won't ignite",
                                                                index: index, active: nil) else {
            return XCTFail("another manufacturer's machine is still refused")
        }
    }

    func testASeriesMemberSplitByTheTranscriberIsJoinedBackUp() {
        XCTAssertEqual(index.seriesMember(in: "OK furnace Lennox SLP 99UH090XV36BK"), "SLP99UH090XV36BK")
        XCTAssertEqual(index.seriesMember(in: "furnace SLP99UH090XV36BK"), "SLP99UH090XV36BK")
        XCTAssertNil(index.seriesMember(in: "furnace won't ignite, error E240"))
    }

    func testAVaultWithoutACommonSeriesHasNone() {
        let mixed = VaultModelIndex(vaultName: "Chillers", files: [("models.md", """
        ## 30RB060 (air-cooled scroll)
        ## 19XR450 (centrifugal)
        """)])
        XCTAssertNil(mixed.seriesStem)
        XCTAssertNil(mixed.series(of: "30RB070"))
    }
}
