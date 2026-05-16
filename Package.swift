// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BetterScreenTimeRegressionTests",
    platforms: [
        .macOS(.v13)
    ],
    products: [],
    targets: [
        .target(
            name: "BetterScreenTimeCore",
            path: "BetterScreenTime/BetterScreenTime",
            exclude: [
                "Assets.xcassets",
                "BetterScreenTime.app",
                "BetterScreenTime.entitlements",
                "BetterScreenTimeApp.swift",
                "AppColors.swift",
                "AppIconProvider.swift",
                "ContentView.swift",
                "DetailView.swift",
                "GanttView.swift",
                "HeaderView.swift",
                "SidebarView.swift"
            ]
        ),
        .testTarget(
            name: "RegressionTests",
            dependencies: ["BetterScreenTimeCore"],
            path: "Tests/RegressionTests"
        )
    ]
)
