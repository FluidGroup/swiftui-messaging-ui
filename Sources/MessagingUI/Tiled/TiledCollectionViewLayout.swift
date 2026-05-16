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
    preferredAttributes.frame.size.height != originalAttributes.frame.size.height
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
      if currentItemMetrics().contains(preferredAttributes.indexPath) {
        updateItemHeight(at: preferredAttributes.indexPath, newHeight: newHeight)
      }
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
    var sections: [[ItemMetric]] = []
    var currentY = anchorY

    for section in sectionItemCounts.indices {
      var sectionItems: [ItemMetric] = []
      for item in 0..<sectionItemCounts.itemCount(in: section) {
        let indexPath = IndexPath(item: item, section: section)
        let height = itemSize(at: indexPath, width: width)?.height ?? estimatedHeight
        sectionItems.append(ItemMetric(yPosition: currentY, height: height))
        currentY += height
      }
      sections.append(sectionItems)
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

    itemMetrics.prepareForMutation(using: targetSectionItemCounts)

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

    itemMetrics.prepareForMutation(using: targetSectionItemCounts)

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

    itemMetrics.prepareForMutation(using: targetSectionItemCounts)
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

    itemMetrics.prepareForMutation(using: targetSectionItemCounts)
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

  private func replaceItemMetrics(_ sections: [[ItemMetric]]) {
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

  // MARK: - Private Helpers

  /// Recalculates all item heights and Y positions when width becomes available.
  private func recalculateAllHeights(width: CGFloat) {
    guard !itemMetrics.isEmpty else { return }

    var currentY = anchorY
    var sections: [[ItemMetric]] = []

    for section in itemMetrics.sectionItemCounts.indices {
      var sectionItems: [ItemMetric] = []
      for item in 0..<itemMetrics.sectionItemCounts.itemCount(in: section) {
        let indexPath = IndexPath(item: item, section: section)
        let height = itemSize(at: indexPath, width: width)?.height ?? estimatedHeight
        sectionItems.append(ItemMetric(yPosition: currentY, height: height))
        currentY += height
      }
      sections.append(sectionItems)
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

  private struct ItemMetrics {
    private var sections: [[ItemMetric]] = []

    var count: Int {
      sections.reduce(0) { $0 + $1.count }
    }

    var isEmpty: Bool {
      count == 0
    }

    var sectionItemCounts: SectionItemCounts {
      SectionItemCounts(sections.map(\.count))
    }

    var firstItem: ItemMetric? {
      for section in sections {
        if let item = section.first {
          return item
        }
      }
      return nil
    }

    var lastItem: ItemMetric? {
      for section in sections.reversed() {
        if let item = section.last {
          return item
        }
      }
      return nil
    }

    func contains(_ indexPath: IndexPath) -> Bool {
      item(at: indexPath) != nil
    }

    func item(at indexPath: IndexPath) -> ItemMetric? {
      guard indexPath.section >= 0,
            indexPath.section < sections.count,
            indexPath.item >= 0,
            indexPath.item < sections[indexPath.section].count else {
        return nil
      }
      return sections[indexPath.section][indexPath.item]
    }

    func items(intersecting rect: CGRect) -> [(indexPath: IndexPath, metric: ItemMetric)] {
      var result: [(indexPath: IndexPath, metric: ItemMetric)] = []

      for sectionIndex in sections.indices {
        let section = sections[sectionIndex]
        guard !section.isEmpty else { continue }

        if let lastItem = section.last,
           lastItem.yPosition + lastItem.height < rect.minY {
          continue
        }

        if let firstItem = section.first,
           firstItem.yPosition > rect.maxY {
          break
        }

        let firstItemIndex = firstPotentiallyVisibleItemIndex(in: section, rect: rect)
        for itemIndex in firstItemIndex..<section.count {
          let metric = section[itemIndex]
          if metric.yPosition > rect.maxY {
            break
          }
          result.append((
            indexPath: IndexPath(item: itemIndex, section: sectionIndex),
            metric: metric
          ))
        }
      }

      return result
    }

    func itemBefore(_ indexPath: IndexPath) -> ItemMetric? {
      guard !sections.isEmpty else { return nil }
      guard indexPath.section < sections.count else { return lastItem }

      if indexPath.section >= 0 {
        let itemEndIndex = min(max(indexPath.item, 0), sections[indexPath.section].count)
        if itemEndIndex > 0 {
          return sections[indexPath.section][itemEndIndex - 1]
        }
      }

      guard indexPath.section > 0 else { return nil }
      for sectionIndex in stride(from: indexPath.section - 1, through: 0, by: -1) {
        if let item = sections[sectionIndex].last {
          return item
        }
      }

      return nil
    }

    func firstItem(atOrAfter indexPath: IndexPath) -> ItemMetric? {
      guard indexPath.section >= 0,
            indexPath.section < sections.count else { return nil }

      let itemStartIndex = min(max(indexPath.item, 0), sections[indexPath.section].count)
      if itemStartIndex < sections[indexPath.section].count {
        return sections[indexPath.section][itemStartIndex]
      }

      let nextSection = indexPath.section + 1
      guard nextSection < sections.count else { return nil }
      for sectionIndex in nextSection..<sections.count {
        if let item = sections[sectionIndex].first {
          return item
        }
      }

      return nil
    }

    mutating func prepareForMutation(using sectionItemCounts: SectionItemCounts) {
      while sections.count < sectionItemCounts.count {
        sections.append([])
      }

      if sections.count > sectionItemCounts.count {
        sections.removeLast(sections.count - sectionItemCounts.count)
      }
    }

    func assertItemCounts(match sectionItemCounts: SectionItemCounts) {
      assert(
        self.sectionItemCounts == sectionItemCounts,
        "Item metrics are inconsistent with collection view section item counts."
      )
    }

    mutating func insert(_ items: [ItemMetric], at indexPath: IndexPath) {
      guard indexPath.section >= 0 else { return }
      while sections.count <= indexPath.section {
        sections.append([])
      }

      let insertionIndex = min(max(indexPath.item, 0), sections[indexPath.section].count)
      sections[indexPath.section].insert(contentsOf: items, at: insertionIndex)
    }

    mutating func removeItem(at indexPath: IndexPath) -> ItemMetric? {
      guard indexPath.section >= 0,
            indexPath.section < sections.count,
            indexPath.item >= 0,
            indexPath.item < sections[indexPath.section].count else {
        return nil
      }

      return sections[indexPath.section].remove(at: indexPath.item)
    }

    mutating func updateItemHeight(at indexPath: IndexPath, newHeight: CGFloat) {
      guard indexPath.section >= 0,
            indexPath.section < sections.count,
            indexPath.item >= 0,
            indexPath.item < sections[indexPath.section].count else {
        return
      }

      sections[indexPath.section][indexPath.item].height = newHeight
    }

    mutating func shiftItem(at indexPath: IndexPath, by delta: CGFloat) {
      guard delta != 0,
            indexPath.section >= 0,
            indexPath.section < sections.count,
            indexPath.item >= 0,
            indexPath.item < sections[indexPath.section].count else {
        return
      }

      sections[indexPath.section][indexPath.item].yPosition += delta
    }

    mutating func shiftItems(before indexPath: IndexPath, by delta: CGFloat) {
      guard delta != 0 else { return }

      for sectionIndex in sections.indices {
        if sectionIndex < indexPath.section {
          shiftItems(in: sectionIndex, by: delta)
        } else if sectionIndex == indexPath.section {
          let endIndex = min(max(indexPath.item, 0), sections[sectionIndex].count)
          shiftItems(in: sectionIndex, range: 0..<endIndex, by: delta)
          return
        } else {
          return
        }
      }
    }

    mutating func shiftItems(after indexPath: IndexPath, by delta: CGFloat) {
      guard delta != 0 else { return }

      for sectionIndex in sections.indices {
        if sectionIndex < indexPath.section {
          continue
        } else if sectionIndex == indexPath.section {
          let startIndex = min(max(indexPath.item + 1, 0), sections[sectionIndex].count)
          shiftItems(in: sectionIndex, range: startIndex..<sections[sectionIndex].count, by: delta)
        } else {
          shiftItems(in: sectionIndex, by: delta)
        }
      }
    }

    mutating func shiftItems(atOrAfter indexPath: IndexPath, by delta: CGFloat) {
      guard delta != 0 else { return }

      for sectionIndex in sections.indices {
        if sectionIndex < indexPath.section {
          continue
        } else if sectionIndex == indexPath.section {
          let startIndex = min(max(indexPath.item, 0), sections[sectionIndex].count)
          shiftItems(in: sectionIndex, range: startIndex..<sections[sectionIndex].count, by: delta)
        } else {
          shiftItems(in: sectionIndex, by: delta)
        }
      }
    }

    mutating func replaceSections(_ sections: [[ItemMetric]]) {
      self.sections = sections
    }

    mutating func removeAll() {
      sections.removeAll(keepingCapacity: true)
    }

    private func firstPotentiallyVisibleItemIndex(in section: [ItemMetric], rect: CGRect) -> Int {
      var low = 0
      var high = section.count

      while low < high {
        let mid = (low + high) / 2
        let itemBottom = section[mid].yPosition + section[mid].height

        if itemBottom < rect.minY {
          low = mid + 1
        } else {
          high = mid
        }
      }

      return low
    }

    private mutating func shiftItems(in sectionIndex: Int, by delta: CGFloat) {
      shiftItems(in: sectionIndex, range: 0..<sections[sectionIndex].count, by: delta)
    }

    private mutating func shiftItems(
      in sectionIndex: Int,
      range: Range<Int>,
      by delta: CGFloat
    ) {
      for itemIndex in range {
        sections[sectionIndex][itemIndex].yPosition += delta
      }
    }
  }

  private struct SectionItemCounts: Equatable {
    private var itemCounts: [Int]

    init(_ itemCounts: [Int]) {
      self.itemCounts = itemCounts.map { max($0, 0) }
    }

    init(validating itemCounts: [Int], expectedTotalItemCount: Int) {
      let itemCounts = itemCounts.map { max($0, 0) }
      if itemCounts.reduce(0, +) != expectedTotalItemCount {
        assertionFailure("Section item counts must match the expected total item count.")
      }
      self.itemCounts = itemCounts
    }

    var count: Int {
      itemCounts.count
    }

    var indices: Range<Int> {
      itemCounts.indices
    }

    var totalItemCount: Int {
      itemCounts.reduce(0, +)
    }

    func itemCount(in section: Int) -> Int {
      guard section >= 0, section < itemCounts.count else { return 0 }
      return itemCounts[section]
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
    let counts = sectionItemCountsProvider?() ?? [expectedItemCount]
    return SectionItemCounts(
      validating: counts,
      expectedTotalItemCount: expectedItemCount
    )
  }

  private func observedSectionItemCounts(in collectionView: UICollectionView) -> SectionItemCounts {
    guard collectionView.numberOfSections > 0 else {
      return SectionItemCounts([])
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
