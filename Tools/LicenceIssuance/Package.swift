// swift-tools-version: 5.9
import PackageDescription
// On Linux (the licence service's containers) CryptoKit is swift-crypto's `Crypto`; on Apple platforms nothing is fetched into the build.
let crypto: Target.Dependency = .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))
let package = Package(name: "LicenceIssuance", platforms: [.macOS(.v13)], products: [
    .library(name: "LicenceIssuance", targets: ["LicenceIssuance"]),
    .executable(name: "licence-issuance", targets: ["licence-issuance"]),
    .executable(name: "generate-field-license", targets: ["generate-field-license"]),
    .executable(name: "make-org-profile", targets: ["make-org-profile"])
], dependencies: [
    .package(url: "https://github.com/apple/swift-crypto.git", exact: "5.0.1")
], targets: [
    .target(name: "LicenceIssuance", dependencies: [crypto]),
    .executableTarget(name: "licence-issuance", dependencies: ["LicenceIssuance", crypto]),
    .executableTarget(name: "generate-field-license", dependencies: ["LicenceIssuance", crypto]),
    .executableTarget(name: "make-org-profile", dependencies: ["LicenceIssuance", crypto]),
    .testTarget(name: "LicenceIssuanceTests", dependencies: ["LicenceIssuance", crypto])
])
