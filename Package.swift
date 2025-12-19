// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "swiftui-messaging-ui",
  platforms: [
    .iOS(.v17)
  ],
  products: [
    .library(
      name: "MessagingUI",
      targets: ["MessagingUI"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-collections", from: "1.3.0"),
    .package(url: "https://github.com/FluidGroup/swift-with-prerender", from: "1.1.0"),
    .package(url: "https://github.com/FluidGroup/swift-rubber-banding", from: "1.0.0"),
  ],
  targets: [
    .target(
      name: "MessagingUI",
      dependencies: [
        .product(name: "DequeModule", package: "swift-collections"),
        .product(name: "WithPrerender", package: "swift-with-prerender"),
        .product(name: "RubberBanding", package: "swift-rubber-banding"),
      ]
    ),
    .testTarget(
      name: "MessagingUITests",
      dependencies: ["MessagingUI"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
