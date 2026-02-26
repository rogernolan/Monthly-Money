// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MonthlyMoneyCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "MonthlyMoneyCore", targets: ["MonthlyMoneyCore"])
    ],
    targets: [
        .target(name: "MonthlyMoneyCore"),
        .testTarget(name: "MonthlyMoneyCoreTests", dependencies: ["MonthlyMoneyCore"])
    ]
)
