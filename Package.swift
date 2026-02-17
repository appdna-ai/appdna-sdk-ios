// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppDNASDK",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "AppDNASDK", targets: ["AppDNASDK"])
    ],
    dependencies: [
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "10.0.0"),
        // Optional billing providers (conditionally imported)
        // .package(url: "https://github.com/adaptyteam/AdaptySDK-iOS.git", from: "2.0.0"),
        // .package(url: "https://github.com/RevenueCat/purchases-ios.git", from: "4.0.0"),
    ],
    targets: [
        .target(
            name: "AppDNASDK",
            dependencies: [
                "KeychainAccess",
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
            ]
        ),
        .testTarget(
            name: "AppDNASDKTests",
            dependencies: ["AppDNASDK"]
        )
    ]
)
