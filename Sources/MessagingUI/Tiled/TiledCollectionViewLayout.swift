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

  /// Closure to query item size. Receives index and width, returns size.
  /// If nil is returned, estimatedHeight will be used.
  public var itemSizeProvider: ((_ index: Int, _ width: CGFloat) -> CGSize?)?

  /// Closure to query item size using the section-aware collection view identity.
  /// This is preferred by TiledView; `itemSizeProvider` remains as the linear compatibility path.
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
    let itemCount = metrics.count

    // Add cell items
    if itemCount > 0 {
      // Binary search for first visible item
      let firstIndex = findFirstVisibleIndex(in: rect, metrics: metrics)

      if firstIndex < itemCount {
        for index in firstIndex..<itemCount {
          guard let item = metrics.item(atLinearIndex: index) else { continue }
          let y = item.metric.yPosition

          // Stop if we're past the visible rect
          if y > rect.maxY {
            break
          }

          let height = item.metric.height
          let frame = CGRect(x: 0, y: y, width: boundsWidth, height: height)

          if frame.intersects(rect) {
            let attributes = getOrCreateAttributes(for: item.indexPath, frame: frame)
            result.append(attributes)
          }
        }
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

  // MARK: - Public Item Management API

  public func appendItems(count: Int, startingIndex: Int) {
    let width = collectionView?.bounds.width ?? 0

    if width == 0 {
      needsHeightRecalculation = true
    }

    var items = itemMetrics.flattenedItems()
    let targetSectionMap = currentSectionMap(expectedItemCount: items.count + count)
    for i in 0..<count {
      let index = startingIndex + i
      let height = itemSize(
        atLinearIndex: index,
        in: targetSectionMap,
        width: width
      )?.height ?? estimatedHeight

      let y: CGFloat
      if let lastItem = items.last {
        y = lastItem.yPosition + lastItem.height
      } else {
        y = anchorY
      }
      items.append(ItemMetric(yPosition: y, height: height))
    }

    replaceItemMetrics(items, using: targetSectionMap)
    logCapacity(operation: "appendItems")
  }

  public func prependItems(count: Int) {
    guard count > 0 else { return }

    let width = collectionView?.bounds.width ?? 0

    if width == 0 {
      needsHeightRecalculation = true
    }

    let targetSectionMap = currentSectionMap(expectedItemCount: itemMetrics.count + count)
    insertItemsBeforeKeepingTrailingPositions(count: count, at: 0, targetSectionMap: targetSectionMap)
    logCapacity(operation: "prependItems")
  }

  func insertItemsBeforeKeepingTrailingPositions(count: Int, at index: Int) {
    let targetSectionMap = currentSectionMap(expectedItemCount: itemMetrics.count + count)
    insertItemsBeforeKeepingTrailingPositions(count: count, at: index, targetSectionMap: targetSectionMap)
  }

  private func insertItemsBeforeKeepingTrailingPositions(
    count: Int,
    at index: Int,
    targetSectionMap: TiledSectionMap
  ) {
    guard count > 0 else { return }

    let width = collectionView?.bounds.width ?? 0
    var items = itemMetrics.flattenedItems()
    let insertionIndex = max(0, min(index, items.count))

    if width == 0 {
      needsHeightRecalculation = true
    }

    let heights = (0..<count).map { offset in
      itemSize(
        atLinearIndex: insertionIndex + offset,
        in: targetSectionMap,
        width: width
      )?.height ?? estimatedHeight
    }
    let totalInsertedHeight = heights.reduce(0, +)

    let insertionEndY: CGFloat
    if insertionIndex < items.count {
      insertionEndY = items[insertionIndex].yPosition
    } else if let lastItem = items.last {
      insertionEndY = lastItem.yPosition + lastItem.height
    } else {
      insertionEndY = anchorY
    }

    for i in 0..<insertionIndex {
      items[i].yPosition -= totalInsertedHeight
    }

    var currentY = insertionEndY - totalInsertedHeight
    for (offset, height) in heights.enumerated() {
      items.insert(ItemMetric(yPosition: currentY, height: height), at: insertionIndex + offset)
      currentY += height
    }

    replaceItemMetrics(items, using: targetSectionMap)
    logCapacity(operation: "insertItemsBeforeKeepingTrailingPositions")
  }

  public func insertItems(count: Int, at index: Int) {
    let targetSectionMap = currentSectionMap(expectedItemCount: itemMetrics.count + count)
    insertItems(count: count, at: index, targetSectionMap: targetSectionMap)
  }

  private func insertItems(
    count: Int,
    at index: Int,
    targetSectionMap: TiledSectionMap
  ) {
    guard count > 0 else { return }

    let width = collectionView?.bounds.width ?? 0
    var items = itemMetrics.flattenedItems()
    let insertionIndex = max(0, min(index, items.count))

    if width == 0 {
      needsHeightRecalculation = true
    }

    let startY: CGFloat
    if insertionIndex < items.count {
      startY = items[insertionIndex].yPosition
    } else if let lastItem = items.last {
      startY = lastItem.yPosition + lastItem.height
    } else {
      startY = anchorY
    }

    var currentY = startY
    var totalInsertedHeight: CGFloat = 0

    for i in 0..<count {
      let height = itemSize(
        atLinearIndex: insertionIndex + i,
        in: targetSectionMap,
        width: width
      )?.height ?? estimatedHeight
      items.insert(ItemMetric(yPosition: currentY, height: height), at: insertionIndex + i)
      currentY += height
      totalInsertedHeight += height
    }

    for i in (insertionIndex + count)..<items.count {
      items[i].yPosition += totalInsertedHeight
    }

    replaceItemMetrics(items, using: targetSectionMap)
  }

  func removeItemsKeepingTrailingPositions(at indices: [Int]) {
    let targetSectionMap = currentSectionMap(expectedItemCount: itemMetrics.count - indices.count)
    removeItemsKeepingTrailingPositions(at: indices, targetSectionMap: targetSectionMap)
  }

  private func removeItemsKeepingTrailingPositions(
    at indices: [Int],
    targetSectionMap: TiledSectionMap
  ) {
    guard !indices.isEmpty else { return }

    var items = itemMetrics.flattenedItems()
    let sortedIndices = indices.sorted(by: >)

    for index in sortedIndices {
      guard index >= 0, index < items.count else { continue }

      let removedHeight = items[index].height

      items.remove(at: index)

      for i in 0..<index {
        items[i].yPosition += removedHeight
      }
    }

    replaceItemMetrics(items, using: targetSectionMap)
  }

  public func removeItems(at indices: [Int]) {
    let targetSectionMap = currentSectionMap(expectedItemCount: itemMetrics.count - indices.count)
    removeItems(at: indices, targetSectionMap: targetSectionMap)
  }

  private func removeItems(
    at indices: [Int],
    targetSectionMap: TiledSectionMap
  ) {
    guard !indices.isEmpty else { return }

    var items = itemMetrics.flattenedItems()
    let sortedIndices = indices.sorted(by: >)

    for index in sortedIndices {
      guard index >= 0, index < items.count else { continue }

      let removedHeight = items[index].height

      items.remove(at: index)

      for i in index..<items.count {
        items[i].yPosition -= removedHeight
      }
    }

    replaceItemMetrics(items, using: targetSectionMap)
  }

  public func clear() {
    itemMetrics.removeAll()
    invalidateAttributesCache()
  }

  func beginBatchUpdates() {
    batchUpdateMetrics = currentItemMetrics()
  }

  func endBatchUpdates() {
    batchUpdateMetrics = nil
    invalidateLayout()
  }

  /// Invalidates the attributes cache. Call when IndexPaths change.
  private func invalidateAttributesCache() {
    attributesCache.removeAll(keepingCapacity: true)
  }

  private func replaceItemMetrics(_ items: [ItemMetric], using sectionMap: TiledSectionMap) {
    itemMetrics.replaceItems(items, using: sectionMap)
    invalidateAttributesCache()
  }

  public func updateItemHeight(at index: Int, newHeight: CGFloat) {
    var items = itemMetrics.flattenedItems()
    guard index >= 0, index < items.count else { return }

    let oldHeight = items[index].height
    let heightDiff = newHeight - oldHeight
    guard heightDiff != 0 else { return }

    items[index].height = newHeight

    for i in (index + 1)..<items.count {
      items[i].yPosition += heightDiff
    }

    replaceItemMetrics(items, using: itemMetrics.sectionMap)
  }

  func updateItemHeight(at indexPath: IndexPath, newHeight: CGFloat) {
    guard let index = linearIndex(for: indexPath, in: currentItemMetrics()) else { return }
    updateItemHeight(at: index, newHeight: newHeight)
  }

  func updateItemHeightKeepingTrailingPositions(at index: Int, newHeight: CGFloat) {
    var items = itemMetrics.flattenedItems()
    guard index >= 0, index < items.count else { return }

    let oldHeight = items[index].height
    let heightDiff = newHeight - oldHeight
    guard heightDiff != 0 else { return }

    items[index].height = newHeight
    items[index].yPosition -= heightDiff

    for i in 0..<index {
      items[i].yPosition -= heightDiff
    }

    replaceItemMetrics(items, using: itemMetrics.sectionMap)
  }

  func updateItemHeightKeepingTrailingPositions(at indexPath: IndexPath, newHeight: CGFloat) {
    guard let index = linearIndex(for: indexPath, in: currentItemMetrics()) else { return }
    updateItemHeightKeepingTrailingPositions(at: index, newHeight: newHeight)
  }

  // MARK: - Private Helpers

  /// Recalculates all item heights and Y positions when width becomes available.
  private func recalculateAllHeights(width: CGFloat) {
    guard !itemMetrics.isEmpty else { return }

    var currentY = anchorY
    var items = itemMetrics.flattenedItems()

    for index in items.indices {
      let height = itemSize(
        atLinearIndex: index,
        in: itemMetrics.sectionMap,
        width: width
      )?.height ?? estimatedHeight
      items[index] = ItemMetric(yPosition: currentY, height: height)
      currentY += height
    }

    replaceItemMetrics(items, using: itemMetrics.sectionMap)
  }

  /// Binary search to find the first item that could be visible in the rect.
  ///
  /// Finds the smallest index where the item's bottom edge >= rect.minY.
  /// Items before this index are completely above the visible area.
  ///
  /// Complexity: O(log n) instead of O(n) linear search.
  private func findFirstVisibleIndex(in rect: CGRect, metrics: ItemMetrics) -> Int {
    var low = 0
    var high = metrics.count

    while low < high {
      let mid = (low + high) / 2
      guard let item = metrics.item(atLinearIndex: mid)?.metric else {
        break
      }
      let itemBottom = item.yPosition + item.height

      if itemBottom < rect.minY {
        // Item is completely above visible area, search in right half
        low = mid + 1
      } else {
        // Item may be visible or below, search in left half
        high = mid
      }
    }

    return low
  }

  private func itemSize(
    atLinearIndex linearIndex: Int,
    in sectionMap: TiledSectionMap,
    width: CGFloat
  ) -> CGSize? {
    if let indexPath = sectionMap.indexPath(
      forLinearIndex: linearIndex,
      itemLimit: sectionMap.totalItemCount
    ),
       let size = itemSizeProviderForIndexPath?(indexPath, width) {
      return size
    }

    return itemSizeProvider?(linearIndex, width)
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

    var sectionMap: TiledSectionMap {
      TiledSectionMap(itemCounts: sections.map(\.count))
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

    func item(atLinearIndex linearIndex: Int) -> (indexPath: IndexPath, metric: ItemMetric)? {
      guard let indexPath = sectionMap.indexPath(forLinearIndex: linearIndex, itemLimit: count),
            let metric = item(at: indexPath) else {
        return nil
      }
      return (indexPath, metric)
    }

    func flattenedItems() -> [ItemMetric] {
      sections.flatMap { $0 }
    }

    mutating func replaceItems(_ items: [ItemMetric], using sectionMap: TiledSectionMap) {
      sections.removeAll(keepingCapacity: true)

      var cursor = 0
      for itemCount in sectionMap.itemCounts {
        let endIndex = min(cursor + itemCount, items.count)
        if cursor < endIndex {
          sections.append(Array(items[cursor..<endIndex]))
        } else {
          sections.append([])
        }
        cursor = endIndex
      }
    }

    mutating func removeAll() {
      sections.removeAll(keepingCapacity: true)
    }
  }

  private struct TiledSectionMap: Equatable {
    var itemCounts: [Int]

    init(itemCounts: [Int]) {
      self.itemCounts = itemCounts
    }

    init(validating itemCounts: [Int], fallbackItemCount: Int) {
      if itemCounts.reduce(0, +) == fallbackItemCount {
        self.itemCounts = itemCounts
      } else {
        self.itemCounts = [fallbackItemCount]
      }
    }

    var totalItemCount: Int {
      itemCounts.reduce(0, +)
    }

    func linearIndex(for indexPath: IndexPath, itemLimit: Int) -> Int? {
      guard indexPath.section >= 0,
            indexPath.section < itemCounts.count else {
        return nil
      }

      let sectionItemCount = itemCounts[indexPath.section]
      guard indexPath.item >= 0, indexPath.item < sectionItemCount else {
        return nil
      }

      let precedingItemCount = itemCounts[..<indexPath.section].reduce(0, +)
      let linearIndex = precedingItemCount + indexPath.item
      guard linearIndex < itemLimit else { return nil }
      return linearIndex
    }

    func indexPath(forLinearIndex linearIndex: Int, itemLimit: Int) -> IndexPath? {
      guard linearIndex >= 0, linearIndex < itemLimit else { return nil }

      var remainingIndex = linearIndex
      for (section, itemCount) in itemCounts.enumerated() {
        if remainingIndex < itemCount {
          return IndexPath(item: remainingIndex, section: section)
        }
        remainingIndex -= itemCount
      }

      return nil
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

    if observedSectionMap(in: collectionView) == batchUpdateMetrics.sectionMap {
      return batchUpdateMetrics
    } else {
      return currentMetrics
    }
  }

  private func currentSectionMap(expectedItemCount: Int? = nil) -> TiledSectionMap {
    let expectedItemCount = expectedItemCount ?? itemMetrics.count
    let counts = sectionItemCountsProvider?() ?? [expectedItemCount]
    return TiledSectionMap(validating: counts, fallbackItemCount: expectedItemCount)
  }

  private func observedSectionMap(in collectionView: UICollectionView) -> TiledSectionMap {
    guard collectionView.numberOfSections > 0 else {
      return TiledSectionMap(itemCounts: [])
    }
    let itemCounts = (0..<collectionView.numberOfSections).map { section in
      collectionView.numberOfItems(inSection: section)
    }
    return TiledSectionMap(itemCounts: itemCounts)
  }

  private func applyPendingUpdate(_ update: PendingUpdate) {
    switch update {
    case .insertItems(let count, let indexPath, let positionPreservation):
      let targetSectionMap = targetSectionMapAfterMutation(
        expectedItemCount: itemMetrics.count + count
      )
      guard let index = targetSectionMap.linearIndex(
        for: indexPath,
        itemLimit: itemMetrics.count + count
      ) else { return }

      switch positionPreservation {
      case .itemsBeforeMutation:
        insertItems(count: count, at: index, targetSectionMap: targetSectionMap)
      case .itemsAfterMutation:
        insertItemsBeforeKeepingTrailingPositions(
          count: count,
          at: index,
          targetSectionMap: targetSectionMap
        )
      }

    case .removeItems(let indexPaths, let positionPreservation):
      let indices = linearRemovalIndices(for: indexPaths)
      guard !indices.isEmpty else { return }
      let targetSectionMap = targetSectionMapAfterMutation(
        expectedItemCount: itemMetrics.count - indices.count
      )

      switch positionPreservation {
      case .itemsBeforeMutation:
        removeItems(at: indices, targetSectionMap: targetSectionMap)
      case .itemsAfterMutation:
        removeItemsKeepingTrailingPositions(at: indices, targetSectionMap: targetSectionMap)
      }
    }
  }

  private func linearIndex(for indexPath: IndexPath, in metrics: ItemMetrics) -> Int? {
    metrics.sectionMap.linearIndex(for: indexPath, itemLimit: metrics.count)
  }

  private func linearRemovalIndices(for indexPaths: [IndexPath]) -> [Int] {
    let metrics = batchUpdateMetrics ?? currentItemMetrics()
    return indexPaths.compactMap { indexPath in
      linearIndex(for: indexPath, in: metrics)
    }
  }

  private func targetSectionMapAfterMutation(expectedItemCount: Int) -> TiledSectionMap {
    if let collectionView, collectionView.numberOfSections > 0 {
      let observedSectionMap = observedSectionMap(in: collectionView)
      if observedSectionMap.totalItemCount == expectedItemCount {
        return observedSectionMap
      }
    }

    return currentSectionMap(expectedItemCount: expectedItemCount)
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
