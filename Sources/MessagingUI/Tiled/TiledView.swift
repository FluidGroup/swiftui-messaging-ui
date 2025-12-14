//
//  TiledView.swift
//  TiledView
//
//  Created by Hiroshi Kimura on 2025/12/10.
//

import SwiftUI
import UIKit

// MARK: - TiledViewCell

public final class TiledViewCell: UICollectionViewCell {

  public static let reuseIdentifier = "TiledViewCell"

  /// Custom state for this cell
  public internal(set) var customState: CellState = .empty

  /// Handler called when state changes to update content
  public var _updateConfigurationHandler:
    @MainActor (TiledViewCell, CellState) -> Void = { _, _ in }

  public func configure<Content: View>(with content: Content) {
    contentConfiguration = UIHostingConfiguration {
      content
    }
    .margins(.all, 0)
  }

  /// Update cell content with new state
  public func updateContent(using customState: CellState) {
    self.customState = customState
    _updateConfigurationHandler(self, customState)
  }

  public override func prepareForReuse() {
    super.prepareForReuse()
    contentConfiguration = nil
    customState = .empty
    _updateConfigurationHandler = { _, _ in }
  }

  public override func preferredLayoutAttributesFitting(
    _ layoutAttributes: UICollectionViewLayoutAttributes
  ) -> UICollectionViewLayoutAttributes {
    let attributes = layoutAttributes.copy() as! UICollectionViewLayoutAttributes

    // MagazineLayout方式: contentViewの幅をlayoutAttributesと同期
    if contentView.bounds.width != layoutAttributes.size.width {
      contentView.bounds.size.width = layoutAttributes.size.width
    }

    let targetSize = CGSize(
      width: layoutAttributes.frame.width,
      height: UIView.layoutFittingCompressedSize.height
    )

    let size = contentView.systemLayoutSizeFitting(
      targetSize,
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    )

    attributes.frame.size.height = size.height
    return attributes
  }
}

// MARK: - _TiledView

public final class _TiledView<Item: Identifiable & Equatable, Cell: View>: UIView, UICollectionViewDataSource, UICollectionViewDelegate {

  private let tiledLayout: TiledCollectionViewLayout = .init()
  private var collectionView: UICollectionView!

  private var items: [Item] = []
  private let cellBuilder: (Item, CellState) -> Cell

  /// prototype cell for size measurement
  private let sizingCell = TiledViewCell()

  /// DataSource tracking
  private var lastDataSourceID: UUID?
  private var appliedCursor: Int = 0

  /// Prepend trigger state
  private var isPrependTriggered: Bool = false
  private let prependThreshold: CGFloat = 100
  private var prependTask: Task<Void, Never>?

  /// Scroll position tracking
  private var lastAppliedScrollVersion: UInt = 0

  /// Auto-scroll to bottom on append
  var autoScrollsToBottomOnAppend: Bool = false

  /// Scroll geometry change callback
  var onScrollGeometryChange: ((TiledScrollGeometry) -> Void)?

  /// Per-item cell state storage
  private var stateMap: [Item.ID: CellState] = [:]

  public typealias DataSource = ListDataSource<Item>

  public let onPrepend: (@MainActor () async throws -> Void)?

  public init(
    cellBuilder: @escaping (Item, CellState) -> Cell,
    onPrepend: (@MainActor () async throws -> Void)? = nil
  ) {
    self.cellBuilder = cellBuilder
    self.onPrepend = onPrepend
    super.init(frame: .zero)

    do {
      tiledLayout.itemSizeProvider = { [weak self] index, width in
        self?.measureSize(at: index, width: width)
      }
      
      collectionView = UICollectionView(frame: .zero, collectionViewLayout: tiledLayout)
      collectionView.translatesAutoresizingMaskIntoConstraints = false
      collectionView.selfSizingInvalidation = .enabledIncludingConstraints
      collectionView.backgroundColor = .systemBackground
      collectionView.allowsSelection = true
      collectionView.dataSource = self
      collectionView.delegate = self
      collectionView.alwaysBounceVertical = true
      
      collectionView.register(TiledViewCell.self, forCellWithReuseIdentifier: TiledViewCell.reuseIdentifier)
      
      addSubview(collectionView)
      
      NSLayoutConstraint.activate([
        collectionView.topAnchor.constraint(equalTo: topAnchor),
        collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
        collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
        collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
      ])
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
 
  private func measureSize(at index: Int, width: CGFloat) -> CGSize? {
    guard index < items.count else { return nil }
    let item = items[index]
    let state = stateMap[item.id] ?? .empty

    // Measure using the same UIHostingConfiguration approach
    sizingCell.configure(with: cellBuilder(item, state))
    sizingCell.layoutIfNeeded()

    let targetSize = CGSize(
      width: width,
      height: UIView.layoutFittingCompressedSize.height
    )

    let size = sizingCell.contentView.systemLayoutSizeFitting(
      targetSize,
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    )
    return size
  }

  // MARK: - DataSource-based API

  /// Applies changes from a ListDataSource.
  /// Uses cursor tracking to apply only new changes since last application.
  public func applyDataSource(_ dataSource: ListDataSource<Item>) {
    // Check if this is a new DataSource instance
    if lastDataSourceID != dataSource.id {
      lastDataSourceID = dataSource.id
      appliedCursor = 0
      tiledLayout.clear()
      items.removeAll()
    }

    // Apply only changes after the cursor
    let pendingChanges = dataSource.pendingChanges
    guard appliedCursor < pendingChanges.count else {
      return 
    }

    let newChanges = pendingChanges[appliedCursor...]
    for change in newChanges {
      applyChange(change, from: dataSource)
    }
    appliedCursor = pendingChanges.count
  }

  private func applyChange(_ change: ListDataSource<Item>.Change, from dataSource: ListDataSource<Item>) {
    switch change {
    case .setItems:
      tiledLayout.clear()
      items = Array(dataSource.items)
      tiledLayout.appendItems(count: items.count, startingIndex: 0)
      collectionView.reloadData()

    case .prepend(let ids):
      let newItems = ids.compactMap { id in dataSource.items.first { $0.id == id } }
      items.insert(contentsOf: newItems, at: 0)
      tiledLayout.prependItems(count: newItems.count)
      collectionView.reloadData()

    case .append(let ids):
      let startingIndex = items.count
      let newItems = ids.compactMap { id in dataSource.items.first { $0.id == id } }
      items.append(contentsOf: newItems)
      tiledLayout.appendItems(count: newItems.count, startingIndex: startingIndex)
      collectionView.reloadData()

      if autoScrollsToBottomOnAppend {
        scrollToBottom(animated: true)
      }

    case .insert(let index, let ids):
      let newItems = ids.compactMap { id in dataSource.items.first { $0.id == id } }
      for (offset, item) in newItems.enumerated() {
        items.insert(item, at: index + offset)
      }
      tiledLayout.insertItems(count: newItems.count, at: index)
      collectionView.reloadData()

    case .update(let ids):
      for id in ids {
        if let index = items.firstIndex(where: { $0.id == id }),
           let newItem = dataSource.items.first(where: { $0.id == id }) {
          items[index] = newItem
        }
      }
      collectionView.reloadData()

    case .remove(let ids):
      let idsSet = Set(ids)
      // Find indices before removing items
      let indicesToRemove = items.enumerated()
        .filter { idsSet.contains($0.element.id) }
        .map { $0.offset }
      items.removeAll { idsSet.contains($0.id) }
      tiledLayout.removeItems(at: indicesToRemove)
      collectionView.reloadData()
    }
  }

  // MARK: UICollectionViewDataSource

  public func numberOfSections(in collectionView: UICollectionView) -> Int {
    1
  }

  public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    items.count
  }

  public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TiledViewCell.reuseIdentifier, for: indexPath) as! TiledViewCell
    let item = items[indexPath.item]
    let state = stateMap[item.id] ?? .empty

    cell.configure(with: cellBuilder(item, state))
    cell.customState = state
    cell._updateConfigurationHandler = { [weak self] cell, newState in
      guard let self else { return }
      cell.configure(with: self.cellBuilder(item, newState))
    }

    return cell
  }

  // MARK: UICollectionViewDelegate

  public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    // Override in subclass or use closure if needed
  }

  // MARK: - UIScrollViewDelegate

  public func scrollViewDidScroll(_ scrollView: UIScrollView) {
    let offsetY = scrollView.contentOffset.y + scrollView.contentInset.top

    if offsetY <= prependThreshold {
      if !isPrependTriggered && prependTask == nil {
        isPrependTriggered = true
        prependTask = Task { @MainActor [weak self] in
          defer { self?.prependTask = nil }
          try? await self?.onPrepend?()
        }
      }
    } else {
      isPrependTriggered = false
    }

    // Notify scroll geometry change
    if let onScrollGeometryChange {
      let geometry = TiledScrollGeometry(
        contentOffset: scrollView.contentOffset,
        contentSize: scrollView.contentSize,
        visibleSize: scrollView.bounds.size,
        contentInset: scrollView.adjustedContentInset
      )
      onScrollGeometryChange(geometry)
    }
  }

  // MARK: - Scroll Position

  func applyScrollPosition(_ position: TiledScrollPosition) {
    guard position.version > lastAppliedScrollVersion else { return }
    lastAppliedScrollVersion = position.version

    guard let edge = position.edge else { return }

    // Derive content bounds from adjustedContentInset
    // (adjustedContentInset includes contentInset + safe area + keyboard adjustments)
    let inset = collectionView.adjustedContentInset
    let contentTop = -inset.top
    let contentBottom = collectionView.contentSize.height + inset.bottom

    let boundsWidth = collectionView.bounds.width

    let targetRect: CGRect
    switch edge {
    case .top:
      targetRect = CGRect(x: 0, y: contentTop, width: boundsWidth, height: 1)
    case .bottom:
      targetRect = CGRect(x: 0, y: contentBottom - 1, width: boundsWidth, height: 1)
    }

    collectionView.scrollRectToVisible(targetRect, animated: position.animated)
    collectionView.flashScrollIndicators()
  }

  private func scrollToBottom(animated: Bool) {
    collectionView.layoutIfNeeded()
    guard items.count > 0 else { return }

    let inset = collectionView.adjustedContentInset
    let contentBottom = collectionView.contentSize.height + inset.bottom
    let boundsWidth = collectionView.bounds.width
    let targetRect = CGRect(x: 0, y: contentBottom - 1, width: boundsWidth, height: 1)

    collectionView.scrollRectToVisible(targetRect, animated: animated)
  }

  // MARK: - Cell State Management

  /// Sets the entire CellState for an item (internal use)
  func _setState(cellState: CellState, for itemId: Item.ID) {
    stateMap[itemId] = cellState

    // Update visible cell if exists
    if let index = items.firstIndex(where: { $0.id == itemId }),
       let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0))
         as? TiledViewCell {
      cell.updateContent(using: cellState)
    }
  }

  /// Sets an individual state value for an item
  public func setState<Key: CustomStateKey>(
    _ value: Key.Value,
    key: Key.Type,
    for itemId: Item.ID
  ) {
    var state = stateMap[itemId, default: .empty]
    state[Key.self] = value
    stateMap[itemId] = state

    if let index = items.firstIndex(where: { $0.id == itemId }),
       let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0))
         as? TiledViewCell {
      cell.updateContent(using: state)
    }
  }

  /// Gets a state value for an item
  public func state<Key: CustomStateKey>(for itemId: Item.ID, key: Key.Type) -> Key.Value {
    stateMap[itemId]?[Key.self] ?? Key.defaultValue
  }

  /// Resets all cell states
  public func resetState() {
    stateMap.removeAll()

    for cell in collectionView.visibleCells {
      if let tiledCell = cell as? TiledViewCell {
        tiledCell.customState = .empty
        tiledCell.updateContent(using: .empty)
      }
    }
  }
}

// MARK: - TiledView

/// A high-performance SwiftUI list view built on UICollectionView,
/// designed for chat/messaging applications with bidirectional infinite scrolling.
///
/// ## Key Features
///
/// - **Virtual Content Layout**: Uses a 100M point virtual content height with anchor point,
///   enabling smooth prepend/append operations without content offset jumps.
/// - **Self-Sizing Cells**: Automatic cell height calculation using UIHostingConfiguration.
/// - **Efficient Updates**: Change-based updates (prepend, append, insert, remove, update)
///   without full reload.
/// - **Cell State Management**: Optional per-cell state storage that persists across reuse.
///
/// ## Architecture
///
/// ```
/// TiledView (SwiftUI)
///     └── _TiledView (UIView)
///             ├── UICollectionView
///             │       └── TiledViewCell (UIHostingConfiguration)
///             └── TiledCollectionViewLayout (Custom Layout)
/// ```
///
/// ## Basic Usage
///
/// ```swift
/// struct ChatView: View {
///   @State private var dataSource = ListDataSource<Message>()
///   @State private var scrollPosition = TiledScrollPosition()
///
///   var body: some View {
///     TiledView(
///       dataSource: dataSource,
///       scrollPosition: $scrollPosition
///     ) { message, state in
///       MessageBubbleView(message: message)
///     }
///     .onAppear {
///       dataSource.setItems(initialMessages)
///     }
///   }
/// }
/// ```
///
/// ## ListDataSource
///
/// Use ``ListDataSource`` to manage items. It tracks changes for efficient updates:
///
/// ```swift
/// dataSource.setItems([...])        // Replace all items
/// dataSource.prepend([...])         // Add to beginning (older messages)
/// dataSource.append([...])          // Add to end (newer messages)
/// dataSource.insert([...], at: 5)   // Insert at specific index
/// dataSource.update([...])          // Update existing items
/// dataSource.remove(ids: [...])     // Remove by IDs
/// dataSource.applyDiff(from: [...]) // Auto-detect changes
/// ```
///
/// ## TiledScrollPosition
///
/// Control scroll position programmatically with ``TiledScrollPosition``:
///
/// ```swift
/// @State private var scrollPosition = TiledScrollPosition()
///
/// // Scroll to edges
/// scrollPosition.scrollTo(edge: .top)
/// scrollPosition.scrollTo(edge: .bottom, animated: true)
///
/// // Auto-scroll on append (for chat "stick to bottom" behavior)
/// scrollPosition.autoScrollsToBottomOnAppend = true
/// ```
///
/// ## Cell State (Optional)
///
/// Store per-cell state that persists across cell reuse using ``CellState`` and ``CustomStateKey``:
///
/// ```swift
/// // 1. Define a state key
/// enum IsExpandedKey: CustomStateKey {
///   typealias Value = Bool
///   static var defaultValue: Bool { false }
/// }
///
/// // 2. Use state in cell builder
/// TiledView(dataSource: dataSource, scrollPosition: $scrollPosition) { item, state in
///   let isExpanded = state[IsExpandedKey.self]
///   MyCell(item: item, isExpanded: isExpanded)
/// }
/// ```
///
/// ## Scroll Geometry
///
/// Monitor scroll position for "scroll to bottom" buttons using ``TiledScrollGeometry``:
///
/// ```swift
/// TiledView(...)
///   .onScrollGeometryChange { geometry in
///     let isNearBottom = geometry.pointsFromBottom < 100
///   }
/// ```
///
/// ## Infinite Scrolling
///
/// Use `onPrepend` to load older content when scrolling near top:
///
/// ```swift
/// TiledView(
///   dataSource: dataSource,
///   scrollPosition: $scrollPosition,
///   onPrepend: {
///     let olderMessages = await api.fetchOlderMessages()
///     dataSource.prepend(olderMessages)
///   }
/// ) { ... }
/// ```
///
/// ## Virtual Content Layout Details
///
/// The layout uses a virtual content height of 100,000,000 points with items
/// anchored at the center (50,000,000). This provides ~50M points of scroll
/// space in each direction, eliminating content offset adjustments during
/// prepend/append operations.
///
/// Content bounds are exposed via negative contentInset values, which mask
/// the unused virtual space above/below the actual content.
public struct TiledView<Item: Identifiable & Equatable, Cell: View>: UIViewRepresentable {

  public typealias UIViewType = _TiledView<Item, Cell>

  let dataSource: ListDataSource<Item>
  let cellBuilder: (Item, CellState) -> Cell
  let cellStates: [Item.ID: CellState]?
  let onPrepend: (@MainActor () async throws -> Void)?
  var onScrollGeometryChange: ((TiledScrollGeometry) -> Void)?
  @Binding var scrollPosition: TiledScrollPosition

  public init(
    dataSource: ListDataSource<Item>,
    scrollPosition: Binding<TiledScrollPosition>,
    cellStates: [Item.ID: CellState]? = nil,
    onPrepend: (@MainActor () async throws -> Void)? = nil,
    @ViewBuilder cellBuilder: @escaping (Item, CellState) -> Cell
  ) {
    self.dataSource = dataSource
    self._scrollPosition = scrollPosition
    self.cellStates = cellStates
    self.onPrepend = onPrepend
    self.cellBuilder = cellBuilder
  }

  public func makeUIView(context: Context) -> _TiledView<Item, Cell> {
    let view = _TiledView(cellBuilder: cellBuilder, onPrepend: onPrepend)
    view.applyDataSource(dataSource)
    view.onScrollGeometryChange = onScrollGeometryChange
    return view
  }

  public func updateUIView(_ uiView: _TiledView<Item, Cell>, context: Context) {
    uiView.autoScrollsToBottomOnAppend = scrollPosition.autoScrollsToBottomOnAppend
    uiView.onScrollGeometryChange = onScrollGeometryChange
    uiView.applyDataSource(dataSource)
    uiView.applyScrollPosition(scrollPosition)

    // Apply external cellStates if provided
    if let cellStates {
      for (id, state) in cellStates {
        uiView._setState(cellState: state, for: id)
      }
    }
  }

  public consuming func onScrollGeometryChange(
    _ action: @escaping (TiledScrollGeometry) -> Void
  ) -> Self {
    self.onScrollGeometryChange = action
    return self
  }
}
