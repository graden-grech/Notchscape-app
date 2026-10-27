// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AccountStorageRegression",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AccountStorageRegression", targets: ["AccountStorageRegression"])],
    dependencies: [
        .package(url: "https://github.com/auth0/Auth0.swift", exact: "3.1.0"),
        .package(url: "https://github.com/auth0/SimpleKeychain.git", exact: "1.3.0")
    ],
    targets: [.executableTarget(
        name: "AccountStorageRegression",
        dependencies: [.product(name: "Auth0", package: "Auth0.swift"),
                       .product(name: "SimpleKeychain", package: "SimpleKeychain")],
        path: ".",
        sources: ["AccountCredentialStorage.swift", "StorageRegression.swift"]
    )]
)
