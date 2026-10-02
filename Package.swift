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
    .library(
      name: "MessagingCell",
      targets: ["MessagingCell"]
    ),
    .library(
      name: "ContextOverlay",
      targets: ["ContextOverlay"]
    ),
  ],
  dependencies: [
    .package(path: "Vendor/swiftui-snap-dragging-modifier"),
    .package(url: "https://github.com/Aeastr/UIPortalBridge", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-collections", from: "1.3.0"),
    .package(url: "https://github.com/FluidGroup/swift-with-prerender", from: "1.1.0"),
    .package(url: "https://github.com/FluidGroup/swift-rubber-banding", from: "1.0.0"),
  ],
  targets: [
    // Cell rendering and reply gestures can be used without a TiledView.
    .target(name: "MessagingCell", dependencies: [
      "ContextOverlay",
      .product(name: "SwiftUISnapDraggingModifier", package: "swiftui-snap-dragging-modifier"),
    ]),
    .target(name: "ContextOverlay", dependencies: [
      .product(name: "UIPortalBridge", package: "UIPortalBridge"),
    ]),
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
    .testTarget(
      name: "MessagingCellTests",
      dependencies: ["MessagingCell"]
    ),
    .testTarget(
      name: "ContextOverlayTests",
      dependencies: ["ContextOverlay"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
