import SwiftUI
import Testing
import UIKit
@testable import MessagingUI

/// Exercises UIKit's update lifecycle with message and accessory snapshots together.
@Suite(.serialized)
@MainActor
struct TiledViewUpdateTests {

  @Test
  func accessoryInsertionAndPrependPreserveExistingMessageFrames() async throws {
    let host = try Host()
    defer { host.close() }
    let initialItems = (10...14).map { Item(id: $0) }

    host.apply(items: initialItems)
    try await host.waitForSnapshot(items: initialItems, sectionCounts: [0, 0, 5, 0, 0])
    let originalFrames = try initialItems.indices.map { index in
      try host.messageFrame(at: index)
    }

    let prependedItems = (8...14).map { Item(id: $0) }
    host.apply(
      items: prependedItems,
      hasPrependLoader: true,
      hasAppendLoader: true,
      hasTypingIndicator: true,
      header: "conversation-header"
    )
    try await host.waitForSnapshot(items: prependedItems, sectionCounts: [1, 1, 7, 1, 1])

    // Fixed-height content makes a frame change evidence of the structural update,
    // rather than a later preferred-size correction from SwiftUI.
    for index in initialItems.indices {
      let currentFrame = try host.messageFrame(at: index + 2)
      #expect(currentFrame == originalFrames[index])
      #expect(currentFrame.height == 40)
    }
    try host.expectContiguousFrames(sectionCounts: [1, 1, 7, 1, 1])
  }

  @Test
  func rapidSnapshotsCommitLatestMessageAndAccessoryStateTogether() async throws {
    let host = try Host()
    defer { host.close() }
    let initialItems = (10...13).map { Item(id: $0) }

    host.apply(
      items: initialItems,
      hasPrependLoader: true,
      hasAppendLoader: true,
      hasTypingIndicator: true,
      header: "initial-header"
    )
    try await host.waitForSnapshot(items: initialItems, sectionCounts: [1, 1, 4, 1, 1])

    // Deliver newer snapshots in the same main-actor turn, before UIKit's batch
    // completions can drain. Accessory removal must share the message update owner.
    host.apply(items: (9...13).map { Item(id: $0) })
    host.apply(
      items: (8...13).map { Item(id: $0) },
      hasPrependLoader: true,
      hasAppendLoader: true,
      header: "intermediate-header"
    )
    let finalItems = [
      Item(id: 7),
      Item(id: 8),
      Item(id: 9),
      Item(id: 10, revision: "updated"),
      Item(id: 12),
      Item(id: 13),
    ]
    host.apply(
      items: finalItems,
      hasTypingIndicator: true,
      header: "final-header"
    )

    try await host.waitForSnapshot(
      items: finalItems,
      sectionCounts: [0, 1, 6, 1, 0],
      headerIdentifier: "final-header"
    )
    try host.expectContiguousFrames(sectionCounts: [0, 1, 6, 1, 0])
  }

  @Test
  func snapshotReceivedDuringPrependMeasurementWaitsForCurrentUpdate() async throws {
    let host = try Host()
    defer { host.close() }
    let initialItems = (10...12).map { Item(id: $0) }
    host.apply(
      items: initialItems,
      hasPrependLoader: true,
      hasAppendLoader: true,
      hasTypingIndicator: true,
      header: "initial-header"
    )
    try await host.waitForSnapshot(items: initialItems, sectionCounts: [1, 1, 3, 1, 1])

    let finalItems = [
      Item(id: 8),
      Item(id: 9),
      Item(id: 10, revision: "reentrant-update"),
      Item(id: 12),
    ]
    var didSubmitReentrantSnapshot = false
    host.onBuild = { item in
      guard item.id == 9 else { return }
      // The size provider builds this newly inserted item from within the layout's
      // batch preparation. Clear the hook before submitting to prevent recursion.
      host.onBuild = nil
      didSubmitReentrantSnapshot = true
      host.apply(items: finalItems, header: "reentrant-header")
    }
    host.apply(
      items: (9...12).map { Item(id: $0) },
      hasPrependLoader: true,
      hasAppendLoader: true,
      hasTypingIndicator: true,
      header: "in-flight-header"
    )

    try await host.waitForSnapshot(
      items: finalItems,
      sectionCounts: [0, 1, 4, 0, 0],
      headerIdentifier: "reentrant-header"
    )
    #expect(didSubmitReentrantSnapshot)
    try host.expectContiguousFrames(sectionCounts: [0, 1, 4, 0, 0])
  }

  @Test
  func typingReappearanceSupersedesDeferredRemoval() async throws {
    let host = try Host()
    defer { host.close() }
    let initialItems = (10...12).map { Item(id: $0) }
    host.apply(items: initialItems)
    try await host.waitForSnapshot(items: initialItems, sectionCounts: [0, 0, 3, 0, 0])

    host.apply(
      items: initialItems,
      hasTypingIndicator: true,
      isTypingVisible: true,
      typingIdentifier: "typing-A"
    )
    try await host.waitForSnapshot(
      items: initialItems,
      sectionCounts: [0, 0, 3, 1, 0],
      typingIdentifier: "typing-A-visible"
    )

    host.apply(items: initialItems, hasTypingIndicator: true, typingIdentifier: "typing-A")
    // Observe the real dismissing phase before re-showing, so the test proves a
    // removal was scheduled rather than merely coalescing away the hidden snapshot.
    try await host.waitForSnapshot(
      items: initialItems,
      sectionCounts: [0, 0, 3, 1, 0],
      typingIdentifier: "typing-A-dismissing"
    )

    let finalItems = (9...12).map { Item(id: $0) }
    host.apply(
      items: finalItems,
      hasTypingIndicator: true,
      isTypingVisible: true,
      typingIdentifier: "typing-B"
    )
    try await host.waitForSnapshot(
      items: finalItems,
      sectionCounts: [0, 0, 4, 1, 0],
      typingIdentifier: "typing-B-visible"
    )

    // Wait beyond both removal deadlines (0.25 s and 0.55 s). An obsolete
    // completion must not hide or reconfigure the newly committed typing payload.
    try await Task.sleep(for: .milliseconds(700))
    try await host.waitForSnapshot(
      items: finalItems,
      sectionCounts: [0, 0, 4, 1, 0],
      typingIdentifier: "typing-B-visible"
    )
    let typingIndexPath = IndexPath(item: 0, section: 3)
    let typingCell = try #require(host.collectionView.cellForItem(at: typingIndexPath))
    let attributes = try #require(host.collectionView.collectionViewLayout.layoutAttributesForItem(
      at: typingIndexPath
    ))
    #expect(typingCell.contentView.alpha == 1)
    #expect(attributes.frame.height == 16)
    try host.expectContiguousFrames(sectionCounts: [0, 0, 4, 1, 0])
  }

  /// Message payloads distinguish content reconfiguration from structural identity.
  private struct Item: Identifiable, Equatable {
    let id: Int
    var revision: String = "original"

    var accessibilityIdentifier: String {
      "message-\(id)-\(revision)"
    }
  }

  /// Provides exact heights and an observable identity in the rendered UIKit cell.
  private struct FixedHeightContent: UIViewRepresentable {
    let identifier: String
    let height: CGFloat

    func makeUIView(context: Context) -> UIView {
      let view = UIView()
      view.accessibilityIdentifier = identifier
      return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
      uiView.accessibilityIdentifier = identifier
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
      CGSize(width: proposal.width ?? 320, height: height)
    }
  }

  /// Hosts real reusable cells without reading TiledUIView's private model storage.
  @MainActor
  private final class Host {
    typealias ViewType = TiledUIView<
      Item, FixedHeightContent, FixedHeightContent, FixedHeightContent,
      FixedHeightContent, FixedHeightContent, Void
    >

    let window: UIWindow
    let view: ViewType
    let collectionView: UICollectionView
    private let buildObserver: BuildObserver

    /// Allows a snapshot to arrive at a deterministic point inside a UIKit update.
    var onBuild: ((Item) -> Void)? {
      get { buildObserver.onBuild }
      set { buildObserver.onBuild = newValue }
    }

    /// Keeps the cell builder independent of the partially initialized host.
    private final class BuildObserver {
      var onBuild: ((Item) -> Void)?
    }

    init() throws {
      let frame = CGRect(x: 0, y: 0, width: 320, height: 640)
      window = UIWindow(frame: frame)
      let controller = UIViewController()
      controller.view.frame = frame
      window.rootViewController = controller
      let buildObserver = BuildObserver()
      self.buildObserver = buildObserver
      view = ViewType(makeInitialState: { _ in () }) { item, _, _ in
        buildObserver.onBuild?(item)
        return FixedHeightContent(identifier: item.accessibilityIdentifier, height: 40)
      }
      view.frame = frame
      view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      controller.view.addSubview(view)
      collectionView = try #require(view.subviews.compactMap { $0 as? UICollectionView }.first)
      window.isHidden = false
      controller.view.layoutIfNeeded()
      view.layoutIfNeeded()
    }

    func close() {
      onBuild = nil
      window.isHidden = true
      window.rootViewController = nil
    }

    func apply(
      items: [Item],
      hasPrependLoader: Bool = false,
      hasAppendLoader: Bool = false,
      hasTypingIndicator: Bool = false,
      isTypingVisible: Bool = false,
      typingIdentifier: String = "typing-indicator",
      header: String? = nil
    ) {
      let prependLoader: Loader<FixedHeightContent>?
      if hasPrependLoader {
        prependLoader = .loader(perform: {}, isProcessing: false) {
          FixedHeightContent(identifier: "prepend-loader", height: 12)
        }
      } else {
        prependLoader = nil
      }
      let appendLoader: Loader<FixedHeightContent>?
      if hasAppendLoader {
        appendLoader = .loader(perform: {}, isProcessing: false) {
          FixedHeightContent(identifier: "append-loader", height: 12)
        }
      } else {
        appendLoader = nil
      }
      let typingIndicator: TypingIndicator<FixedHeightContent>?
      if hasTypingIndicator {
        typingIndicator = .indicator(isVisible: isTypingVisible) { phase in
          let phaseIdentifier: String
          switch phase {
          case .appearing:
            phaseIdentifier = "appearing"
          case .visible:
            phaseIdentifier = "visible"
          case .dismissing:
            phaseIdentifier = "dismissing"
          }
          return FixedHeightContent(identifier: "\(typingIdentifier)-\(phaseIdentifier)", height: 16)
        }
      } else {
        typingIndicator = nil
      }
      let headerContent = header.map { identifier in
        HeaderContent.header {
          FixedHeightContent(identifier: identifier, height: 24)
        }
      }
      view.applySnapshot(
        items: items,
        prependLoader: prependLoader,
        appendLoader: appendLoader,
        typingIndicator: typingIndicator,
        headerContent: headerContent
      )
    }

    func messageFrame(at index: Int) throws -> CGRect {
      let attributes = try #require(collectionView.collectionViewLayout.layoutAttributesForItem(
        at: IndexPath(item: index, section: 2)
      ))
      return attributes.frame
    }

    /// Waits for actual visible content, including reconfigured payloads, not just counts.
    func waitForSnapshot(
      items: [Item],
      sectionCounts: [Int],
      headerIdentifier: String? = nil,
      typingIdentifier: String? = nil
    ) async throws {
      for _ in 0..<200 {
        view.layoutIfNeeded()
        collectionView.layoutIfNeeded()
        if let firstFrame = collectionView.collectionViewLayout.layoutAttributesForItem(
          at: IndexPath(item: 0, section: 2)
        )?.frame {
          // Keep all short test rows and the header inside the viewport.
          collectionView.contentOffset = CGPoint(x: 0, y: firstFrame.minY - 40)
          collectionView.layoutIfNeeded()
        }
        if matches(
          items: items,
          sectionCounts: sectionCounts,
          headerIdentifier: headerIdentifier,
          typingIdentifier: typingIdentifier
        ) {
          return
        }
        try await Task.sleep(for: .milliseconds(10))
      }
      try #require(matches(
        items: items,
        sectionCounts: sectionCounts,
        headerIdentifier: headerIdentifier,
        typingIdentifier: typingIdentifier
      ))
    }

    func expectContiguousFrames(sectionCounts: [Int]) throws {
      var previousFrame: CGRect?
      for (section, count) in sectionCounts.enumerated() {
        for item in 0..<count {
          let attributes = try #require(collectionView.collectionViewLayout.layoutAttributesForItem(
            at: IndexPath(item: item, section: section)
          ))
          if let previousFrame {
            #expect(abs(previousFrame.maxY - attributes.frame.minY) < 0.01)
          }
          previousFrame = attributes.frame
        }
      }
    }

    private func matches(
      items: [Item],
      sectionCounts: [Int],
      headerIdentifier: String?,
      typingIdentifier: String?
    ) -> Bool {
      guard collectionView.numberOfSections == sectionCounts.count else { return false }
      for (section, count) in sectionCounts.enumerated() {
        guard collectionView.numberOfItems(inSection: section) == count else { return false }
        guard view.collectionView(collectionView, numberOfItemsInSection: section) == count else { return false }
      }
      for (index, item) in items.enumerated() {
        guard let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 2)),
              Self.containsIdentifier(item.accessibilityIdentifier, in: cell) else { return false }
      }
      if let headerIdentifier {
        guard let cell = collectionView.cellForItem(at: IndexPath(item: 0, section: 1)),
              Self.containsIdentifier(headerIdentifier, in: cell) else { return false }
      }
      if let typingIdentifier {
        guard let cell = collectionView.cellForItem(at: IndexPath(item: 0, section: 3)),
              Self.containsIdentifier(typingIdentifier, in: cell) else { return false }
      }
      return true
    }

    static func containsIdentifier(_ identifier: String, in view: UIView) -> Bool {
      if view.accessibilityIdentifier == identifier {
        return true
      }
      return view.subviews.contains { containsIdentifier(identifier, in: $0) }
    }
  }
}
