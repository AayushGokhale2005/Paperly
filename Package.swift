// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "PaperlyCore", platforms: [.macOS(.v13)], products: [.library(name: "PaperlyCore", targets: ["PaperlyCore"])], targets: [.target(name: "PaperlyCore", path: "Paperly/Models"), .testTarget(name: "PaperlyCoreTests", dependencies: ["PaperlyCore"], path: "CoreTests")])
