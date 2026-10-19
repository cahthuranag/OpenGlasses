import XCTest
@testable import OpenGlasses

/// `refrigerationUnits` (Plan IS P1): the storefront's default — Australia and New Zealand metric,
/// Canada psig and °F at the gauges with kilograms, everywhere else psig, °F and lb — the stored
/// setting overriding it, and the organisation profile's starting value.
final class RefrigerationUnitsTests: XCTestCase {

    // MARK: - Storefront defaults

    func testAustraliaAndNewZealandDefaultToKPaCelsiusAndKilograms() {
        for code in ["AU", "NZ", "au", "AUS", "NZL"] {
            XCTAssertEqual(RefrigerationUnits.regionDefault(forStorefront: code), .metric, code)
        }
        XCTAssertEqual(RefrigerationUnits.metric,
                       RefrigerationUnits(pressure: .kPa, temperature: .celsius, mass: .kg))
    }

    func testCanadaDefaultsToPsigAndFahrenheitAtTheGaugesAndKilogramsForMass() {
        for code in ["CA", "CAN"] {
            XCTAssertEqual(RefrigerationUnits.regionDefault(forStorefront: code),
                           RefrigerationUnits(pressure: .psi, temperature: .fahrenheit, mass: .kg), code)
        }
    }

    func testEverywhereElseDefaultsToPsigFahrenheitAndPounds() {
        for code in ["US", "GB", "DE", "JP", "", nil] as [String?] {
            XCTAssertEqual(RefrigerationUnits.regionDefault(forStorefront: code), .imperial, code ?? "nil")
        }
        XCTAssertEqual(RefrigerationUnits.imperial,
                       RefrigerationUnits(pressure: .psi, temperature: .fahrenheit, mass: .lb))
    }

    // MARK: - The setting overrides the default

    func testAStoredChoiceOverridesTheRegionDefault() {
        XCTAssertEqual(RefrigerationUnits.effective(stored: "kPa,C,kg", storefront: "US"), .metric)
        XCTAssertEqual(RefrigerationUnits.effective(stored: "psi,F,lb", storefront: "AU"), .imperial)
        XCTAssertEqual(RefrigerationUnits.effective(stored: "bar,C,kg", storefront: "CA"),
                       RefrigerationUnits(pressure: .bar, temperature: .celsius, mass: .kg))
    }

    func testNothingStoredOrSomethingUnreadableFollowsTheRegion() {
        XCTAssertEqual(RefrigerationUnits.effective(stored: nil, storefront: "NZ"), .metric)
        XCTAssertEqual(RefrigerationUnits.effective(stored: "", storefront: "NZ"), .metric)
        XCTAssertEqual(RefrigerationUnits.effective(stored: "furlongs", storefront: "CA"), .canadian)
        XCTAssertEqual(RefrigerationUnits.effective(stored: "kPa,C", storefront: "US"), .imperial)
    }

    func testTheStoredFormRoundTripsAndToleratesHowPeopleWriteIt() {
        for units in [RefrigerationUnits.metric, .imperial, .canadian,
                      RefrigerationUnits(pressure: .bar, temperature: .fahrenheit, mass: .lb)] {
            XCTAssertEqual(RefrigerationUnits(encoded: units.encoded), units)
        }
        XCTAssertEqual(RefrigerationUnits.metric.encoded, "kPa,C,kg")
        XCTAssertEqual(RefrigerationUnits(encoded: " KPA, °c , KG "), .metric)
        XCTAssertEqual(RefrigerationUnits(encoded: "psig,°F,lbs"), .imperial)
        XCTAssertNil(RefrigerationUnits(encoded: "kPa,K,kg"))
    }

    func testTheSettingChangesHowAnAnswerIsRenderedNotWhatIsComputed() throws {
        let json: [String: Any] = ["readings": [
            ["quantity": "pressure", "value": 118, "unit": "psig", "confidence": 0.9, "label": "LOW"],
            ["quantity": "temperature", "value": 50, "unit": "°F", "confidence": 0.9, "label": "SUCTION"],
        ], "summary": "Fixture."]
        let readings = try InstrumentReadingSchema().makeCard(from: json, context: nil).readings
        func answer(_ stored: String?, storefront: String) -> String {
            var request = RefrigerantGaugeChain.Request()
            request.calculations = [.superheat]
            request.refrigerant = RefrigerantIdentity(designation: "R-410A", source: .nameplate)
            request.units = RefrigerationUnits.effective(stored: stored, storefront: storefront)
            return RefrigerantGaugeChain.run(readings: readings, request: request) {
                SaturationTableCatalog.table(for: $0)
            }.text
        }
        XCTAssertTrue(answer(nil, storefront: "US").hasPrefix("Superheat 10.2 °F:"))
        XCTAssertTrue(answer(nil, storefront: "AU").hasPrefix("Superheat 5.6 K:"), answer(nil, storefront: "AU"))
        XCTAssertTrue(answer("psi,F,lb", storefront: "AU").hasPrefix("Superheat 10.2 °F:"),
                      "the technician's choice beats the region")
    }

    // MARK: - The organisation profile's starting value

    private func apply(_ value: ProfileValue) -> ProfileApplier.Result {
        let profile = ConfigProfile(keyId: "test-key", profileId: "p", organizationName: "Northbridge Mechanical",
                                    issued: Date(timeIntervalSince1970: 1_790_000_000), leaseDays: 30,
                                    eraseAfterLapseDays: nil, undeliveredEraseDays: nil,
                                    settings: ["refrigerationUnits": RawSetting(value, .default)])
        return ProfileApplier.apply(profile: profile, resolvableVaultIds: [])
    }

    func testAProfileMayOfferUnitsTheTechnicianCanChange() {
        XCTAssertEqual(SettingKey.refrigerationUnits.rawValue, RefrigerationUnitsSetting.key,
                       "the profile writes the key the setting reads")
        XCTAssertEqual(SettingKey.refrigerationUnits.kind, .startingValue(.string))
        let result = apply(.string("kPa,C,kg"))
        XCTAssertEqual(result.startingValues[.refrigerationUnits], .string("kPa,C,kg"))
        XCTAssertTrue(result.drops.isEmpty)
        XCTAssertFalse(result.isLocked(.refrigerationUnits))
        XCTAssertEqual(SettingKey.refrigerationUnits.startingValueDescription(.string("kPa,C,kg")),
                       "Refrigeration answers start in kPa, °C and kg")
    }

    func testAProfileWithUnitsThisBuildCannotReadIsANamedDrop() {
        let result = apply(.string("metric"))
        XCTAssertNil(result.startingValues[.refrigerationUnits])
        XCTAssertEqual(result.drops, [.init(key: "refrigerationUnits", reason: .invalidValue(
            "not units written as pressure,temperature,mass (for example kPa,C,kg)"))])
    }
}
