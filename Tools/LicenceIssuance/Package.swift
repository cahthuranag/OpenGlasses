// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "LicenceIssuance", platforms: [.macOS(.v13)], products: [
    .library(name: "LicenceIssuance", targets: ["LicenceIssuance"]),
    .executable(name: "licence-issuance", targets: ["licence-issuance"]),
    .executable(name: "generate-field-license", targets: ["generate-field-license"]),
    .executable(name: "make-org-profile", targets: ["make-org-profile"])
], targets: [
    .target(name: "LicenceIssuance"),
    .executableTarget(name: "licence-issuance", dependencies: ["LicenceIssuance"]),
    .executableTarget(name: "generate-field-license", dependencies: ["LicenceIssuance"]),
    .executableTarget(name: "make-org-profile", dependencies: ["LicenceIssuance"]),
    .testTarget(name: "LicenceIssuanceTests", dependencies: ["LicenceIssuance"])
])
