//
//  TiledCollectionViewLayout.swift
//  TiledView
//
//  Created by Hiroshi Kimura on 2025/12/10.
//

import UIKit

// MARK: - TiledCollectionViewLayout

public final class TiledCollectionViewLayout: UICollectionViewLayout {

  // MARK: - Configuration

  /// Closure to query item size using the section-aware collection view identity.
  var itemSizeProviderForIndexPath: ((_ indexPath: IndexPath, _ width: CGFloat) -> CGSize?)?

  /// Closure to query item counts for each visual section in layout order.
  var sectionItemCountsProvider: (() -> [Int])?

  /// Additional content inset to apply on top of the calculated inset.
  /// Use this to add extra space for keyboard, headers, footers, etc.
  public var additionalContentInset: UIEdgeInsets = .zero

  // MARK: - Constants

  private let virtualContentHeight: CGFloat = 100_000_000
  private let anchorY: CGFloat = 50_000_000
  private let estimatedHeight: CGFloat = 100

  // MARK: - Private State

  /// On-demand cache for layout attributes (IGListKit-style).
  /// Attributes are created when requested and cached for reuse.
  private var attributesCache: [IndexPath: UICollectionViewLayoutAttributes] = [:]
  private var itemMetrics = ItemMetrics()
  private var lastPreparedBoundsWidth: CGFloat = 0
  /// Metrics from before a batch mutation. UICollectionView can ask for
  /// old-count attributes while our data source already exposes the new items.
  private var batchUpdateMetrics: ItemMetrics?

  /// Tracks whether item heights need recalculation due to width being 0 at initial add time.
  private var needsHeightRecalculation: Bool = false

  /// Structural update to apply from `prepare(forCollectionViewUpdates:)`.
  enum PendingUpdate {
    case insertItems(count: Int, at: IndexPath, preserving: PositionPreservation)
    case removeItems(at: [IndexPath], preserving: PositionPreservation)
  }

  enum PositionPreservation {
    case itemsBeforeMutation
    case itemsAfterMutation
  }

  enum DisplaySection: Int, CaseIterable {
    case prependLoader
    case headerContent
    case messages
    case typingIndicator
    case appendLoader

    static let allCases: [DisplaySection] = [
      .prependLoader,
      .headerContent,
      .messages,
      .typingIndicator,
      .appendLoader,
    ]

    static let reversedCases = Array(allCases.reversed())

    static var count: Int {
      allCases.count
    }

    func indexPath(item: Int = 0) -> IndexPath {
      IndexPath(item: item, section: rawValue)
    }

    var shouldPreserveTrailingPositionsWhenSelfSizing: Bool {
      switch self {
      case .prependLoader, .headerContent:
        true
      case .messages, .typingIndicator, .appendLoader:
        false
      }
    }
  }

  private var pendingUpdate: PendingUpdate?

  /// Edge content that should keep its cell height but not expand the scrollable content bounds.
  var hiddenEdgeContentInset: UIEdgeInsets = .zero {
    didSet {
      guard hiddenEdgeContentInset != oldValue else { return }
      invalidateLayout()
    }
  }

  // MARK: - UICollectionViewLayout Overrides

  public override var collectionViewContentSize: CGSize {
    CGSize(
      width: collectionView?.bounds.width ?? 0,
      height: virtualContentHeight
    )
  }

  public override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
    collectionView?.bounds.size != newBounds.size
  }

  public override func prepare() {
    guard let collectionView else { return }

    let boundsWidth = collectionView.bounds.width

    // Recalculate heights if they were added when width was 0
    if needsHeightRecalculation && boundsWidth > 0 {
      recalculateAllHeights(width: boundsWidth)
      needsHeightRecalculation = false
    }

    // Invalidate cache if width changed
    if lastPreparedBoundsWidth != boundsWidth {
      attributesCache.removeAll(keepingCapacity: true)
      lastPreparedBoundsWidth = boundsWidth
    }

    // Automatically update contentInset
    collectionView.contentInset = calculateContentInset()
  }

  public override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
    var result: [UICollectionViewLayoutAttributes] = []

    let boundsWidth = collectionView?.bounds.width ?? 0

    let metrics = activeItemMetrics()
    for item in metrics.items(intersecting: rect) {
      let height = item.metric.height
      let frame = CGRect(
        x: 0,
        y: item.metric.yPosition,
        width: boundsWidth,
        height: height
      )

      if frame.intersects(rect) {
        let attributes = getOrCreateAttributes(for: item.indexPath, frame: frame)
        result.append(attributes)
      }
    }

    return result
  }

  public override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
    let metrics = activeItemMetrics()

    guard let item = metrics.item(at: indexPath) else { return nil }

    let boundsWidth = collectionView?.bounds.width ?? 0
    let frame = CGRect(
      x: 0,
      y: item.yPosition,
      width: boundsWidth,
      height: item.height
    )

    return getOrCreateAttributes(for: indexPath, frame: frame)
  }

  /// Gets cached attributes or creates new ones (IGListKit-style on-demand caching).
  private func getOrCreateAttributes(for indexPath: IndexPath, frame: CGRect) -> UICollectionViewLayoutAttributes {
    if batchUpdateMetrics != nil {
      let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
      attributes.frame = frame
      return attributes
    }

    if let cached = attributesCache[indexPath] {
      // Update frame in case position changed
      cached.frame = frame
      return cached
    }

    let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
    attributes.frame = frame
    attributesCache[indexPath] = attributes
    return attributes
  }

  // MARK: - Self-Sizing Support

  public override func shouldInvalidateLayout(
    forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes,
    withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes
  ) -> Bool {
    guard !shouldSuppressSelfSizingInvalidationDuringBatchUpdates else { return false }
    return preferredAttributes.frame.size.height != originalAttributes.frame.size.height
  }

  /// Returns whether preferred-size invalidation should be blocked while UIKit
  /// is resolving a collection-view batch update.
  private var shouldSuppressSelfSizingInvalidationDuringBatchUpdates: Bool {
    guard batchUpdateMetrics != nil else { return false }

    // UIKit can ask visible cells from both pre-update and post-update
    // snapshots for preferred sizes while a batch update is resolving on
    // affected OS versions. Starting another self-sizing invalidation in that
    // window can recurse through visible-cell updates before either snapshot
    // settles. iOS 26 and newer keep the default self-sizing behavior.
    if #available(iOS 26.0, *) {
      return false
    } else {
      return true
    }
  }

  public override func invalidationContext(
    forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes,
    withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes
  ) -> UICollectionViewLayoutInvalidationContext {
    let context = super.invalidationContext(
      forPreferredLayoutAttributes: preferredAttributes,
      withOriginalAttributes: originalAttributes
    )

    let newHeight = preferredAttributes.frame.size.height

    if preferredAttributes.representedElementCategory == .cell {
      updateItemHeightForSelfSizing(at: preferredAttributes.indexPath, newHeight: newHeight)
    }

    return context
  }

  // MARK: - Batch Update Hooks

  func enqueuePendingUpdate(_ update: PendingUpdate) {
    assert(pendingUpdate == nil, "TiledCollectionViewLayout only supports one pending structural update per batch.")
    pendingUpdate = update
  }

  public override func prepare(forCollectionViewUpdates updateItems: [UICollectionViewUpdateItem]) {
    super.prepare(forCollectionViewUpdates: updateItems)

    guard let update = pendingUpdate else { return }
    pendingUpdate = nil

    applyPendingUpdate(update)

    if let collectionView {
      collectionView.contentInset = calculateContentInset(using: currentItemMetrics())
    }
  }

  public override func finalizeCollectionViewUpdates() {
    super.finalizeCollectionViewUpdates()
    pendingUpdate = nil
  }

  // MARK: - Item Management

  func resetItemMetrics(expectedItemCount: Int) {
    let width = collectionView?.bounds.width ?? 0

    if width == 0 {
      needsHeightRecalculation = true
    }

    let sectionItemCounts = currentSectionItemCounts(expectedItemCount: expectedItemCount)
    var sections = ItemMetricSections()
    var currentY = anchorY

    for section in DisplaySection.allCases {
      var sectionItems: [ItemMetric] = []
      for item in 0..<sectionItemCounts.itemCount(in: section) {
        let indexPath = section.indexPath(item: item)
        let height = itemSize(at: indexPath, width: width)?.height ?? estimatedHeight
        sectionItems.append(ItemMetric(yPosition: currentY, height: height))
        currentY += height
      }
      sections.setItems(sectionItems, in: section)
    }

    replaceItemMetrics(sections)
    logCapacity(operation: "resetItemMetrics")
  }

  private func insertItemsBeforeKeepingTrailingPositions(
    count: Int,
    at indexPath: IndexPath,
    targetSectionItemCounts: SectionItemCounts
  ) {
    guard count > 0 else { return }

    let width = collectionView?.bounds.width ?? 0

    if width == 0 {
      needsHeightRecalculation = true
    }

    let heights = insertedItemHeights(
      count: count,
      startingAt: indexPath,
      width: width
    )
    let totalInsertedHeight = heights.reduce(0, +)

    let insertionEndY: CGFloat
    if let item = itemMetrics.item(at: indexPath) {
      insertionEndY = item.yPosition
    } else if let nextItem = itemMetrics.firstItem(atOrAfter: indexPath) {
      insertionEndY = nextItem.yPosition
    } else if let lastItem = itemMetrics.lastItem {
      insertionEndY = lastItem.yPosition + lastItem.height
    } else {
      insertionEndY = anchorY
    }

    itemMetrics.shiftItems(before: indexPath, by: -totalInsertedHeight)

    var currentY = insertionEndY - totalInsertedHeight
    let insertedItems = heights.map { height in
      defer { currentY += height }
      return ItemMetric(yPosition: currentY, height: height)
    }

    itemMetrics.insert(insertedItems, at: indexPath)
    itemMetrics.assertItemCounts(match: targetSectionItemCounts)

    invalidateAttributesCache()
    logCapacity(operation: "insertItemsBeforeKeepingTrailingPositions")
  }

  private func insertItems(
    count: Int,
    at indexPath: IndexPath,
    targetSectionItemCounts: SectionItemCounts
  ) {
    guard count > 0 else { return }

    let width = collectionView?.bounds.width ?? 0

    if width == 0 {
      needsHeightRecalculation = true
    }

    let heights = insertedItemHeights(
      count: count,
      startingAt: indexPath,
      width: width
    )
    let totalInsertedHeight = heights.reduce(0, +)

    let startY: CGFloat
    if let item = itemMetrics.item(at: indexPath) {
      startY = item.yPosition
    } else if let lastItem = itemMetrics.itemBefore(indexPath) {
      startY = lastItem.yPosition + lastItem.height
    } else {
      startY = anchorY
    }

    itemMetrics.shiftItems(atOrAfter: indexPath, by: totalInsertedHeight)

    var currentY = startY
    let insertedItems = heights.map { height in
      defer { currentY += height }
      return ItemMetric(yPosition: currentY, height: height)
    }

    itemMetrics.insert(insertedItems, at: indexPath)
    itemMetrics.assertItemCounts(match: targetSectionItemCounts)

    invalidateAttributesCache()
  }

  private func removeItemsKeepingTrailingPositions(
    at indexPaths: [IndexPath],
    targetSectionItemCounts: SectionItemCounts
  ) {
    guard !indexPaths.isEmpty else { return }

    for indexPath in indexPaths.sortedInDescendingDisplayOrder() {
      guard let removedItem = itemMetrics.item(at: indexPath) else { continue }
      itemMetrics.shiftItems(before: indexPath, by: removedItem.height)
      _ = itemMetrics.removeItem(at: indexPath)
    }

    itemMetrics.assertItemCounts(match: targetSectionItemCounts)
    invalidateAttributesCache()
  }

  private func removeItems(
    at indexPaths: [IndexPath],
    targetSectionItemCounts: SectionItemCounts
  ) {
    guard !indexPaths.isEmpty else { return }

    for indexPath in indexPaths.sortedInDescendingDisplayOrder() {
      guard let removedItem = itemMetrics.removeItem(at: indexPath) else { continue }
      itemMetrics.shiftItems(atOrAfter: indexPath, by: -removedItem.height)
    }

    itemMetrics.assertItemCounts(match: targetSectionItemCounts)
    invalidateAttributesCache()
  }

  public func clear() {
    itemMetrics.removeAll()
    invalidateAttributesCache()
  }

  func beginBatchUpdates() {
    assert(batchUpdateMetrics == nil, "TiledCollectionViewLayout is already in a batch update.")
    batchUpdateMetrics = currentItemMetrics()
  }

  func endBatchUpdates() {
    assert(batchUpdateMetrics != nil, "TiledCollectionViewLayout is not in a batch update.")
    batchUpdateMetrics = nil
    invalidateLayout()
  }

  /// Invalidates the attributes cache. Call when IndexPaths change.
  private func invalidateAttributesCache() {
    attributesCache.removeAll(keepingCapacity: true)
  }

  private func replaceItemMetrics(_ sections: ItemMetricSections) {
    itemMetrics.replaceSections(sections)
    invalidateAttributesCache()
  }

  func updateItemHeight(at indexPath: IndexPath, newHeight: CGFloat) {
    guard let item = itemMetrics.item(at: indexPath) else { return }
    let oldHeight = item.height
    let heightDiff = newHeight - oldHeight
    guard heightDiff != 0 else { return }

    itemMetrics.updateItemHeight(at: indexPath, newHeight: newHeight)
    itemMetrics.shiftItems(after: indexPath, by: heightDiff)
    invalidateAttributesCache()
  }

  func updateItemHeightKeepingTrailingPositions(at indexPath: IndexPath, newHeight: CGFloat) {
    guard let item = itemMetrics.item(at: indexPath) else { return }
    let oldHeight = item.height
    let heightDiff = newHeight - oldHeight
    guard heightDiff != 0 else { return }

    itemMetrics.updateItemHeight(at: indexPath, newHeight: newHeight)
    itemMetrics.shiftItem(at: indexPath, by: -heightDiff)
    itemMetrics.shiftItems(before: indexPath, by: -heightDiff)
    invalidateAttributesCache()
  }

  private func updateItemHeightForSelfSizing(at indexPath: IndexPath, newHeight: CGFloat) {
    guard currentItemMetrics().contains(indexPath) else { return }
    guard let section = DisplaySection(rawValue: indexPath.section) else { return }

    if section.shouldPreserveTrailingPositionsWhenSelfSizing {
      updateItemHeightKeepingTrailingPositions(at: indexPath, newHeight: newHeight)
    } else {
      updateItemHeight(at: indexPath, newHeight: newHeight)
    }
  }

  // MARK: - Private Helpers

  /// Recalculates all item heights and Y positions when width becomes available.
  private func recalculateAllHeights(width: CGFloat) {
    guard !itemMetrics.isEmpty else { return }

    var currentY = anchorY
    var sections = ItemMetricSections()

    for section in DisplaySection.allCases {
      var sectionItems: [ItemMetric] = []
      for item in 0..<itemMetrics.sectionItemCounts.itemCount(in: section) {
        let indexPath = section.indexPath(item: item)
        let height = itemSize(at: indexPath, width: width)?.height ?? estimatedHeight
        sectionItems.append(ItemMetric(yPosition: currentY, height: height))
        currentY += height
      }
      sections.setItems(sectionItems, in: section)
    }

    replaceItemMetrics(sections)
  }

  private func insertedItemHeights(
    count: Int,
    startingAt indexPath: IndexPath,
    width: CGFloat
  ) -> [CGFloat] {
    (0..<count).map { offset in
      let insertedIndexPath = IndexPath(
        item: indexPath.item + offset,
        section: indexPath.section
      )
      return itemSize(at: insertedIndexPath, width: width)?.height ?? estimatedHeight
    }
  }

  private func itemSize(at indexPath: IndexPath, width: CGFloat) -> CGSize? {
    itemSizeProviderForIndexPath?(indexPath, width)
  }

  private struct ItemMetric {
    var yPosition: CGFloat
    var height: CGFloat
  }

  private struct ItemMetricSections {
    private var prependLoader: ItemMetric?
    private var headerContent: ItemMetric?
    private var messages: [ItemMetric] = []
    private var typingIndicator: ItemMetric?
    private var appendLoader: ItemMetric?

    var count: Int {
      itemCount(in: .prependLoader)
        + itemCount(in: .headerContent)
        + messages.count
        + itemCount(in: .typingIndicator)
        + itemCount(in: .appendLoader)
    }

    var sectionItemCounts: SectionItemCounts {
      SectionItemCounts(
        prependLoader: itemCount(in: .prependLoader),
        headerContent: itemCount(in: .headerContent),
        messages: messages.count,
        typingIndicator: itemCount(in: .typingIndicator),
        appendLoader: itemCount(in: .appendLoader)
      )
    }

    func itemCount(in section: DisplaySection) -> Int {
      switch section {
      case .prependLoader:
        optionalItemCount(prependLoader)
      case .headerContent:
        optionalItemCount(headerContent)
      case .messages:
        messages.count
      case .typingIndicator:
        optionalItemCount(typingIndicator)
      case .appendLoader:
        optionalItemCount(appendLoader)
      }
    }

    func firstItem(in section: DisplaySection) -> ItemMetric? {
      item(at: 0, in: section)
    }

    func lastItem(in section: DisplaySection) -> ItemMetric? {
      switch section {
      case .prependLoader:
        prependLoader
      case .headerContent:
        headerContent
      case .messages:
        messages.last
      case .typingIndicator:
        typingIndicator
      case .appendLoader:
        appendLoader
      }
    }

    func item(at index: Int, in section: DisplaySection) -> ItemMetric? {
      switch section {
      case .prependLoader:
        return index == 0 ? prependLoader : nil
      case .headerContent:
        return index == 0 ? headerContent : nil
      case .messages:
        guard index >= 0, index < messages.count else { return nil }
        return messages[index]
      case .typingIndicator:
        return index == 0 ? typingIndicator : nil
      case .appendLoader:
        return index == 0 ? appendLoader : nil
      }
    }

    func firstPotentiallyVisibleItemIndex(in section: DisplaySection, rect: CGRect) -> Int {
      switch section {
      case .messages:
        firstPotentiallyVisibleMessageIndex(rect: rect)
      case .prependLoader, .headerContent, .typingIndicator, .appendLoader:
        0
      }
    }

    mutating func setItems(_ items: [ItemMetric], in section: DisplaySection) {
      switch section {
      case .prependLoader:
        prependLoader = accessoryItem(from: items)
      case .headerContent:
        headerContent = accessoryItem(from: items)
      case .messages:
        messages = items
      case .typingIndicator:
        typingIndicator = accessoryItem(from: items)
      case .appendLoader:
        appendLoader = accessoryItem(from: items)
      }
    }

    mutating func insert(_ items: [ItemMetric], at indexPath: IndexPath) {
      guard let section = DisplaySection(rawValue: indexPath.section) else { return }
      switch section {
      case .messages:
        let insertionIndex = min(max(indexPath.item, 0), messages.count)
        messages.insert(contentsOf: items, at: insertionIndex)
      case .prependLoader, .headerContent, .typingIndicator, .appendLoader:
        assert(items.count <= 1, "Accessory sections can contain at most one item.")
        assert(itemCount(in: section) == 0, "Accessory sections can contain at most one item.")
        guard indexPath.item == 0,
              let item = items.first else { return }
        setAccessoryItem(item, in: section)
      }
    }

    mutating func removeItem(at indexPath: IndexPath) -> ItemMetric? {
      guard let section = DisplaySection(rawValue: indexPath.section) else { return nil }

      switch section {
      case .messages:
        guard indexPath.item >= 0,
              indexPath.item < messages.count else {
          return nil
        }
        return messages.remove(at: indexPath.item)
      case .prependLoader, .headerContent, .typingIndicator, .appendLoader:
        guard indexPath.item == 0 else { return nil }
        return takeAccessoryItem(in: section)
      }
    }

    mutating func updateItem(
      at indexPath: IndexPath,
      _ body: (inout ItemMetric) -> Void
    ) {
      guard let section = DisplaySection(rawValue: indexPath.section) else { return }

      switch section {
      case .messages:
        guard indexPath.item >= 0,
              indexPath.item < messages.count else {
          return
        }
        body(&messages[indexPath.item])
      case .prependLoader, .headerContent, .typingIndicator, .appendLoader:
        guard indexPath.item == 0 else { return }
        updateAccessoryItem(in: section, body)
      }
    }

    mutating func shiftItems(in section: DisplaySection, by delta: CGFloat) {
      shiftItems(in: section, range: 0..<itemCount(in: section), by: delta)
    }

    mutating func shiftItems(
      in section: DisplaySection,
      range: Range<Int>,
      by delta: CGFloat
    ) {
      guard delta != 0 else { return }

      switch section {
      case .messages:
        for itemIndex in range {
          messages[itemIndex].yPosition += delta
        }
      case .prependLoader, .headerContent, .typingIndicator, .appendLoader:
        guard range.contains(0) else { return }
        updateAccessoryItem(in: section) { item in
          item.yPosition += delta
        }
      }
    }

    mutating func removeAll() {
      prependLoader = nil
      headerContent = nil
      messages.removeAll(keepingCapacity: true)
      typingIndicator = nil
      appendLoader = nil
    }

    private func optionalItemCount(_ item: ItemMetric?) -> Int {
      item == nil ? 0 : 1
    }

    private func accessoryItem(from items: [ItemMetric]) -> ItemMetric? {
      assert(items.count <= 1, "Accessory sections can contain at most one item.")
      return items.first
    }

    private mutating func setAccessoryItem(_ item: ItemMetric, in section: DisplaySection) {
      switch section {
      case .prependLoader:
        prependLoader = item
      case .headerContent:
        headerContent = item
      case .messages:
        assertionFailure("Message items are tracked by the message section.")
      case .typingIndicator:
        typingIndicator = item
      case .appendLoader:
        appendLoader = item
      }
    }

    private mutating func takeAccessoryItem(in section: DisplaySection) -> ItemMetric? {
      switch section {
      case .prependLoader:
        defer { prependLoader = nil }
        return prependLoader
      case .headerContent:
        defer { headerContent = nil }
        return headerContent
      case .messages:
        assertionFailure("Message items are tracked by the message section.")
        return nil
      case .typingIndicator:
        defer { typingIndicator = nil }
        return typingIndicator
      case .appendLoader:
        defer { appendLoader = nil }
        return appendLoader
      }
    }

    private mutating func updateAccessoryItem(
      in section: DisplaySection,
      _ body: (inout ItemMetric) -> Void
    ) {
      switch section {
      case .prependLoader:
        Self.updateAccessoryItem(&prependLoader, body)
      case .headerContent:
        Self.updateAccessoryItem(&headerContent, body)
      case .messages:
        assertionFailure("Message items are tracked by the message section.")
      case .typingIndicator:
        Self.updateAccessoryItem(&typingIndicator, body)
      case .appendLoader:
        Self.updateAccessoryItem(&appendLoader, body)
      }
    }

    private static func updateAccessoryItem(
      _ item: inout ItemMetric?,
      _ body: (inout ItemMetric) -> Void
    ) {
      guard var value = item else { return }
      body(&value)
      item = value
    }

    private func firstPotentiallyVisibleMessageIndex(rect: CGRect) -> Int {
      var low = 0
      var high = messages.count

      while low < high {
        let mid = (low + high) / 2
        let itemBottom = messages[mid].yPosition + messages[mid].height

        if itemBottom < rect.minY {
          low = mid + 1
        } else {
          high = mid
        }
      }

      return low
    }
  }

  private struct ItemMetrics {
    private var sections = ItemMetricSections()

    var count: Int {
      sections.count
    }

    var isEmpty: Bool {
      count == 0
    }

    var sectionItemCounts: SectionItemCounts {
      sections.sectionItemCounts
    }

    var firstItem: ItemMetric? {
      for section in DisplaySection.allCases {
        if let item = sections.firstItem(in: section) {
          return item
        }
      }
      return nil
    }

    var lastItem: ItemMetric? {
      for section in DisplaySection.reversedCases {
        if let item = sections.lastItem(in: section) {
          return item
        }
      }
      return nil
    }

    func contains(_ indexPath: IndexPath) -> Bool {
      item(at: indexPath) != nil
    }

    func item(at indexPath: IndexPath) -> ItemMetric? {
      guard let section = DisplaySection(rawValue: indexPath.section) else {
        return nil
      }
      return sections.item(at: indexPath.item, in: section)
    }

    func items(intersecting rect: CGRect) -> [(indexPath: IndexPath, metric: ItemMetric)] {
      var result: [(indexPath: IndexPath, metric: ItemMetric)] = []

      for section in DisplaySection.allCases {
        let itemCount = sections.itemCount(in: section)
        guard itemCount > 0 else { continue }

        if let lastItem = sections.lastItem(in: section),
           lastItem.yPosition + lastItem.height < rect.minY {
          continue
        }

        if let firstItem = sections.firstItem(in: section),
           firstItem.yPosition > rect.maxY {
          break
        }

        let firstItemIndex = sections.firstPotentiallyVisibleItemIndex(in: section, rect: rect)
        for itemIndex in firstItemIndex..<itemCount {
          guard let metric = sections.item(at: itemIndex, in: section) else { continue }
          if metric.yPosition > rect.maxY {
            break
          }
          result.append((
            indexPath: section.indexPath(item: itemIndex),
            metric: metric
          ))
        }
      }

      return result
    }

    func itemBefore(_ indexPath: IndexPath) -> ItemMetric? {
      guard !isEmpty else { return nil }
      guard let section = DisplaySection(rawValue: indexPath.section) else {
        if indexPath.section >= DisplaySection.count {
          return lastItem
        } else {
          return nil
        }
      }

      let itemEndIndex = min(max(indexPath.item, 0), sections.itemCount(in: section))
      if itemEndIndex > 0 {
        return sections.item(at: itemEndIndex - 1, in: section)
      }

      guard section.rawValue > 0 else { return nil }
      for rawValue in stride(from: section.rawValue - 1, through: 0, by: -1) {
        guard let previousSection = DisplaySection(rawValue: rawValue) else { continue }
        if let item = sections.lastItem(in: previousSection) {
          return item
        }
      }

      return nil
    }

    func firstItem(atOrAfter indexPath: IndexPath) -> ItemMetric? {
      guard let section = DisplaySection(rawValue: indexPath.section) else { return nil }

      let itemStartIndex = min(max(indexPath.item, 0), sections.itemCount(in: section))
      if itemStartIndex < sections.itemCount(in: section) {
        return sections.item(at: itemStartIndex, in: section)
      }

      let nextSectionRawValue = section.rawValue + 1
      guard nextSectionRawValue < DisplaySection.count else { return nil }
      for rawValue in nextSectionRawValue..<DisplaySection.count {
        guard let nextSection = DisplaySection(rawValue: rawValue) else { continue }
        if let item = sections.firstItem(in: nextSection) {
          return item
        }
      }

      return nil
    }

    func assertItemCounts(match sectionItemCounts: SectionItemCounts) {
      assert(
        self.sectionItemCounts == sectionItemCounts,
        "Item metrics are inconsistent with collection view section item counts."
      )
    }

    mutating func insert(_ items: [ItemMetric], at indexPath: IndexPath) {
      sections.insert(items, at: indexPath)
    }

    mutating func removeItem(at indexPath: IndexPath) -> ItemMetric? {
      sections.removeItem(at: indexPath)
    }

    mutating func updateItemHeight(at indexPath: IndexPath, newHeight: CGFloat) {
      sections.updateItem(at: indexPath) { item in
        item.height = newHeight
      }
    }

    mutating func shiftItem(at indexPath: IndexPath, by delta: CGFloat) {
      guard delta != 0 else { return }
      sections.updateItem(at: indexPath) { item in
        item.yPosition += delta
      }
    }

    mutating func shiftItems(before indexPath: IndexPath, by delta: CGFloat) {
      guard delta != 0 else { return }

      for section in DisplaySection.allCases {
        if section.rawValue < indexPath.section {
          shiftItems(in: section, by: delta)
        } else if section.rawValue == indexPath.section {
          let endIndex = min(max(indexPath.item, 0), sections.itemCount(in: section))
          shiftItems(in: section, range: 0..<endIndex, by: delta)
          return
        } else {
          return
        }
      }
    }

    mutating func shiftItems(after indexPath: IndexPath, by delta: CGFloat) {
      guard delta != 0 else { return }

      for section in DisplaySection.allCases {
        if section.rawValue < indexPath.section {
          continue
        } else if section.rawValue == indexPath.section {
          let itemCount = sections.itemCount(in: section)
          let startIndex = min(max(indexPath.item + 1, 0), itemCount)
          shiftItems(in: section, range: startIndex..<itemCount, by: delta)
        } else {
          shiftItems(in: section, by: delta)
        }
      }
    }

    mutating func shiftItems(atOrAfter indexPath: IndexPath, by delta: CGFloat) {
      guard delta != 0 else { return }

      for section in DisplaySection.allCases {
        if section.rawValue < indexPath.section {
          continue
        } else if section.rawValue == indexPath.section {
          let itemCount = sections.itemCount(in: section)
          let startIndex = min(max(indexPath.item, 0), itemCount)
          shiftItems(in: section, range: startIndex..<itemCount, by: delta)
        } else {
          shiftItems(in: section, by: delta)
        }
      }
    }

    mutating func replaceSections(_ sections: ItemMetricSections) {
      self.sections = sections
    }

    mutating func removeAll() {
      sections.removeAll()
    }

    private mutating func shiftItems(in section: DisplaySection, by delta: CGFloat) {
      sections.shiftItems(in: section, by: delta)
    }

    private mutating func shiftItems(
      in section: DisplaySection,
      range: Range<Int>,
      by delta: CGFloat
    ) {
      sections.shiftItems(in: section, range: range, by: delta)
    }
  }

  private struct SectionItemCounts: Equatable {
    private let prependLoader: Int
    private let headerContent: Int
    private let messages: Int
    private let typingIndicator: Int
    private let appendLoader: Int

    init() {
      self.init(
        prependLoader: 0,
        headerContent: 0,
        messages: 0,
        typingIndicator: 0,
        appendLoader: 0
      )
    }

    init(messageItemCount: Int) {
      self.init(
        prependLoader: 0,
        headerContent: 0,
        messages: messageItemCount,
        typingIndicator: 0,
        appendLoader: 0
      )
    }

    init(
      prependLoader: Int,
      headerContent: Int,
      messages: Int,
      typingIndicator: Int,
      appendLoader: Int
    ) {
      self.prependLoader = max(prependLoader, 0)
      self.headerContent = max(headerContent, 0)
      self.messages = max(messages, 0)
      self.typingIndicator = max(typingIndicator, 0)
      self.appendLoader = max(appendLoader, 0)
    }

    init(_ itemCounts: [Int]) {
      self.init(
        prependLoader: Self.itemCount(for: .prependLoader, in: itemCounts),
        headerContent: Self.itemCount(for: .headerContent, in: itemCounts),
        messages: Self.itemCount(for: .messages, in: itemCounts),
        typingIndicator: Self.itemCount(for: .typingIndicator, in: itemCounts),
        appendLoader: Self.itemCount(for: .appendLoader, in: itemCounts)
      )
    }

    init(validating itemCounts: [Int], expectedTotalItemCount: Int) {
      self.init(itemCounts)
      if totalItemCount != expectedTotalItemCount {
        assertionFailure("Section item counts must match the expected total item count.")
      }
    }

    var count: Int {
      DisplaySection.count
    }

    var totalItemCount: Int {
      prependLoader
        + headerContent
        + messages
        + typingIndicator
        + appendLoader
    }

    func itemCount(in section: DisplaySection) -> Int {
      switch section {
      case .prependLoader:
        prependLoader
      case .headerContent:
        headerContent
      case .messages:
        messages
      case .typingIndicator:
        typingIndicator
      case .appendLoader:
        appendLoader
      }
    }

    func itemCount(in section: Int) -> Int {
      guard let section = DisplaySection(rawValue: section) else { return 0 }
      return itemCount(in: section)
    }

    private static func itemCount(
      for section: DisplaySection,
      in itemCounts: [Int]
    ) -> Int {
      guard itemCounts.indices.contains(section.rawValue) else { return 0 }
      return max(itemCounts[section.rawValue], 0)
    }
  }

  private func currentItemMetrics() -> ItemMetrics {
    itemMetrics
  }

  private func activeItemMetrics() -> ItemMetrics {
    let currentMetrics = currentItemMetrics()

    guard let batchUpdateMetrics,
          let collectionView,
          collectionView.numberOfSections > 0 else {
      return currentMetrics
    }

    if observedSectionItemCounts(in: collectionView) == batchUpdateMetrics.sectionItemCounts {
      return batchUpdateMetrics
    } else {
      return currentMetrics
    }
  }

  private func currentSectionItemCounts(expectedItemCount: Int? = nil) -> SectionItemCounts {
    let expectedItemCount = expectedItemCount ?? itemMetrics.count
    guard let counts = sectionItemCountsProvider?() else {
      return SectionItemCounts(messageItemCount: expectedItemCount)
    }
    return SectionItemCounts(validating: counts, expectedTotalItemCount: expectedItemCount)
  }

  private func observedSectionItemCounts(in collectionView: UICollectionView) -> SectionItemCounts {
    guard collectionView.numberOfSections > 0 else {
      return SectionItemCounts()
    }
    let itemCounts = (0..<collectionView.numberOfSections).map { section in
      collectionView.numberOfItems(inSection: section)
    }
    return SectionItemCounts(itemCounts)
  }

  private func applyPendingUpdate(_ update: PendingUpdate) {
    switch update {
    case .insertItems(let count, let indexPath, let positionPreservation):
      let targetSectionItemCounts = targetSectionItemCountsAfterMutation(
        expectedItemCount: itemMetrics.count + count
      )

      switch positionPreservation {
      case .itemsBeforeMutation:
        insertItems(
          count: count,
          at: indexPath,
          targetSectionItemCounts: targetSectionItemCounts
        )
      case .itemsAfterMutation:
        insertItemsBeforeKeepingTrailingPositions(
          count: count,
          at: indexPath,
          targetSectionItemCounts: targetSectionItemCounts
        )
      }

    case .removeItems(let indexPaths, let positionPreservation):
      guard !indexPaths.isEmpty else { return }
      let targetSectionItemCounts = targetSectionItemCountsAfterMutation(
        expectedItemCount: itemMetrics.count - indexPaths.count
      )

      switch positionPreservation {
      case .itemsBeforeMutation:
        removeItems(
          at: indexPaths,
          targetSectionItemCounts: targetSectionItemCounts
        )
      case .itemsAfterMutation:
        removeItemsKeepingTrailingPositions(
          at: indexPaths,
          targetSectionItemCounts: targetSectionItemCounts
        )
      }
    }
  }

  private func targetSectionItemCountsAfterMutation(expectedItemCount: Int) -> SectionItemCounts {
    if let collectionView, collectionView.numberOfSections > 0 {
      let observedSectionItemCounts = observedSectionItemCounts(in: collectionView)
      if observedSectionItemCounts.totalItemCount == expectedItemCount {
        return observedSectionItemCounts
      }
    }

    return currentSectionItemCounts(expectedItemCount: expectedItemCount)
  }

  private func contentBounds(in metrics: ItemMetrics) -> (top: CGFloat, bottom: CGFloat)? {
    guard let firstItem = metrics.firstItem,
          let lastItem = metrics.lastItem else { return nil }
    return (firstItem.yPosition, lastItem.yPosition + lastItem.height)
  }

  private func logCapacity(operation: String) {
    guard let bounds = contentBounds(in: currentItemMetrics()) else { return }

    let topPercent = (bounds.top / anchorY) * 100
    let bottomPercent = ((virtualContentHeight - bounds.bottom) / (virtualContentHeight - anchorY)) * 100

    Log.layout.debug("\(operation): top=\(topPercent, format: .fixed(precision: 1))%, bottom=\(bottomPercent, format: .fixed(precision: 1))%")
  }

  // MARK: - Debug Info

  /// Debug information about remaining scroll capacity.
  public struct DebugCapacityInfo {
    /// Remaining scroll space above the first item (in points).
    public let topCapacity: CGFloat
    /// Remaining scroll space below the last item (in points).
    public let bottomCapacity: CGFloat
    /// Total virtual content height.
    public let virtualHeight: CGFloat
    /// Anchor Y position (center point).
    public let anchorY: CGFloat
  }

  /// Returns debug information about remaining scroll capacity.
  /// Useful for monitoring how much virtual space remains for prepend/append operations.
  public var debugCapacityInfo: DebugCapacityInfo? {
    guard let bounds = contentBounds(in: currentItemMetrics()) else { return nil }
    return DebugCapacityInfo(
      topCapacity: bounds.top,
      bottomCapacity: virtualContentHeight - bounds.bottom,
      virtualHeight: virtualContentHeight,
      anchorY: anchorY
    )
  }

  private func calculateContentInset(using metrics: ItemMetrics? = nil) -> UIEdgeInsets {
    let metrics = metrics ?? activeItemMetrics()

    guard let bounds = contentBounds(in: metrics) else {
      // Empty list: treat anchorY as bottom position to appear "at bottom"
      let topInset = anchorY + hiddenEdgeContentInset.top
      let bottomInset = virtualContentHeight - (anchorY - hiddenEdgeContentInset.bottom)
      return UIEdgeInsets(
        top: -topInset + additionalContentInset.top,
        left: additionalContentInset.left,
        bottom: -bottomInset + additionalContentInset.bottom,
        right: additionalContentInset.right
      )
    }

    let topInset = bounds.top + hiddenEdgeContentInset.top
    let bottomInset = virtualContentHeight - (bounds.bottom - hiddenEdgeContentInset.bottom)

    return UIEdgeInsets(
      top: -topInset + additionalContentInset.top,
      left: additionalContentInset.left,
      bottom: -bottomInset + additionalContentInset.bottom,
      right: additionalContentInset.right
    )
  }
}

private extension Array where Element == IndexPath {
  func sortedInDescendingDisplayOrder() -> [IndexPath] {
    sorted { lhs, rhs in
      if lhs.section == rhs.section {
        return lhs.item > rhs.item
      } else {
        return lhs.section > rhs.section
      }
    }
  }
}
