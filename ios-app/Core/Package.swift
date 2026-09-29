// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "LineDrawCore", platforms: [.iOS(.v17), .macOS(.v13)], products: [.library(name: "LineDrawCore", targets: ["LineDrawCore"])], dependencies: [.package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.8.8")], targets: [.target(name: "LineDrawCore", dependencies: ["SwiftSoup"]), .testTarget(name: "LineDrawCoreTests", dependencies: ["LineDrawCore"])])
