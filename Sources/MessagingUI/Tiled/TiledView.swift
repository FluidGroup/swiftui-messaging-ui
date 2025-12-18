//
//  TiledView.swift
//  TiledView
//
//  Created by Hiroshi Kimura on 2025/12/10.
//

import DequeModule
import SwiftUI
import UIKit
import WithPrerender

// MARK: - EdgeInsets Helpers

fileprivate extension EdgeInsets {

  static func + (lhs: EdgeInsets, rhs: EdgeInsets) -> EdgeInsets {
    EdgeInsets(
      top: lhs.top + rhs.top,
      leading: lhs.leading + rhs.leading,
      bottom: lhs.bottom + rhs.bottom,
      trailing: lhs.trailing + rhs.trailing
    )
  }

  func toUIEdgeInsets(layoutDirection: UIUserInterfaceLayoutDirection) -> UIEdgeInsets {
    let isRTL = layoutDirection == .rightToLeft
    return UIEdgeInsets(
      top: top,
      left: isRTL ? trailing : leading,
      bottom: bottom,
      right: isRTL ? leading : trailing
    )
  }
}

fileprivate extension UIEdgeInsets {

  static func - (lhs: UIEdgeInsets, rhs: UIEdgeInsets) -> UIEdgeInsets {
    UIEdgeInsets(
      top: lhs.top - rhs.top,
      left: lhs.left - rhs.left,
      bottom: lhs.bottom - rhs.bottom,
      right: lhs.right - rhs.right
    )
  }
}

// MARK: - TiledViewCell

final class TiledViewCell: UICollectionViewCell {

  static let reuseIdentifier = "TiledViewCell"

  /// Custom state for this cell
  var customState: CellState = .empty

  /// Handler called when state changes to update content
  var _updateConfigurationHandler:
    @MainActor (TiledViewCell, CellState) -> Void = { _, _ in }

  func configure<Content: View>(with content: Content) {
    contentConfiguration = UIHostingConfiguration {
      content
    }
    .margins(.all, 0)
  }

  /// Update cell content with new state
  func updateContent(using customState: CellState) {
    self.customState = customState
    _updateConfigurationHandler(self, customState)
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    contentConfiguration = nil
    customState = .empty
    _updateConfigurationHandler = { _, _ in }
  }

  override func preferredLayoutAttributesFitting(
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

final class _TiledView<Item: Identifiable & Equatable, Cell: View>: UIView, UICollectionViewDataSource, UICollectionViewDelegate {

  private let tiledLayout: TiledCollectionViewLayout = .init()
  private var collectionView: UICollectionView!

  private var items: Deque<Item> = []
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

  /// Spring animator for smooth scroll animations
  private var springAnimator: SpringScrollAnimator?

  /// Auto-scroll to bottom on append
  var autoScrollsToBottomOnAppend: Bool = false

  /// Scroll to bottom on setItems (initial load)
  var scrollsToBottomOnReplace: Bool = false

  /// Scroll geometry change callback
  var onTiledScrollGeometryChange: ((TiledScrollGeometry) -> Void)?

  /// Background tap callback (for dismissing keyboard, etc.)
  var onTapBackground: (() -> Void)?

  /// Callback when dragging into bottom safe area (additionalContentInset.bottom region)
  var onDragIntoBottomSafeArea: (() -> Void)?

  /// Track if already triggered to avoid multiple calls per drag session
  private var hasDraggedIntoBottomSafeArea: Bool = false

  /// Additional content inset for keyboard, headers, footers, etc.
  var additionalContentInset: EdgeInsets = .init() {
    didSet {
      guard additionalContentInset != oldValue else { return }
      applyContentInsets()
    }
  }

  /// Safe area inset from SwiftUI world (passed from GeometryProxy.safeAreaInsets)
  /// This includes also keyboard height when keyboard is presented. and .safeAreaInsets modifier's content.
  var swiftUIWorldSafeAreaInset: EdgeInsets = .init() {
    didSet {
      guard swiftUIWorldSafeAreaInset != oldValue else { return }
      applyContentInsets()
    }
  }

  private func applyContentInsets() {
    // Capture old state to preserve scroll position
    let oldBottomInset = collectionView.adjustedContentInset.bottom
    let oldOffsetY = collectionView.contentOffset.y

    let combined = additionalContentInset + swiftUIWorldSafeAreaInset
    let uiEdgeInsets = combined.toUIEdgeInsets(layoutDirection: effectiveUserInterfaceLayoutDirection) - safeAreaInsets

    // Calculate delta before applying changes
    // Delta = new additionalContentInset.bottom - old additionalContentInset.bottom
    let oldAdditionalBottom = tiledLayout.additionalContentInset.bottom
    let deltaBottom = uiEdgeInsets.bottom - oldAdditionalBottom

    guard deltaBottom != 0 else {
      // Just apply without animation if no change
      tiledLayout.additionalContentInset = uiEdgeInsets
      collectionView.verticalScrollIndicatorInsets.bottom = uiEdgeInsets.bottom
      return
    }

    // Calculate target offset
    var offsetY = oldOffsetY + deltaBottom

    // Pre-calculate overscroll bounds (using new inset values)
    // Note: We estimate the new adjustedContentInset based on the delta
    let estimatedNewAdjustedBottom = oldBottomInset + deltaBottom
    let minOffsetY = -collectionView.adjustedContentInset.top
    let maxOffsetY = collectionView.contentSize.height - collectionView.bounds.height + estimatedNewAdjustedBottom
    offsetY = max(minOffsetY, min(maxOffsetY, offsetY))
    
    let applyChanges = {
      self.collectionView.contentOffset.y = offsetY
      self.tiledLayout.additionalContentInset = uiEdgeInsets
      self.collectionView.verticalScrollIndicatorInsets.bottom = uiEdgeInsets.bottom
      self.tiledLayout.invalidateLayout()
    }

    // Pre-calculate final geometry to notify after animation
    let finalGeometry = TiledScrollGeometry(
      contentOffset: CGPoint(x: collectionView.contentOffset.x, y: offsetY),
      contentSize: collectionView.contentSize,
      visibleSize: collectionView.bounds.size,
      contentInset: UIEdgeInsets(
        top: collectionView.adjustedContentInset.top,
        left: collectionView.adjustedContentInset.left,
        bottom: estimatedNewAdjustedBottom,
        right: collectionView.adjustedContentInset.right
      )
    )

    if #available(iOS 18, *) {
      // context.animate {} in UIViewRepresentable handles animation asynchronously
      applyChanges()
      onTiledScrollGeometryChange?(finalGeometry)
    } else {
      UIView.animate(
        withDuration: 0.5,
        delay: 0,
        options: [.init(rawValue: 7 /* keyboard curve */)]
      ) {
        applyChanges()
      } completion: { _ in
        self.onTiledScrollGeometryChange?(finalGeometry)
      }
    }
  }

  /// Per-item cell state storage
  private var stateMap: [Item.ID: CellState] = [:]
  
  private var pendingActionsOnLayoutSubviews: [() -> Void] = []

  typealias DataSource = ListDataSource<Item>

  let onPrepend: (@MainActor () async throws -> Void)?

  init(
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
      collectionView.backgroundColor = .clear
      collectionView.allowsSelection = false
      collectionView.dataSource = self
      collectionView.delegate = self
      collectionView.alwaysBounceVertical = true
      /// It have to use `.always` as scrolling won't work correctly with `.never`.
      collectionView.contentInsetAdjustmentBehavior = .always
      collectionView.isPrefetchingEnabled = false
      
      collectionView.register(TiledViewCell.self, forCellWithReuseIdentifier: TiledViewCell.reuseIdentifier)

      let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapBackground(_:)))
      tapGesture.cancelsTouchesInView = false
      collectionView.addGestureRecognizer(tapGesture)

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
  
  override func safeAreaInsetsDidChange() {
    super.safeAreaInsetsDidChange()
    applyContentInsets()
  }

  @objc private func handleTapBackground(_ gesture: UITapGestureRecognizer) {
    onTapBackground?()
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
  func applyDataSource(_ dataSource: ListDataSource<Item>) {
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
  
  override func layoutSubviews() {
    super.layoutSubviews()
    
    // Execute any pending actions after layout
    let actions = pendingActionsOnLayoutSubviews
    pendingActionsOnLayoutSubviews.removeAll()
    DispatchQueue.main.async {
      for action in actions {
        action()
      }
    }

  }

  private func applyChange(_ change: ListDataSource<Item>.Change, from dataSource: ListDataSource<Item>) {
    switch change {
    case .replace:
      tiledLayout.clear()
      items = dataSource.items
      tiledLayout.appendItems(count: items.count, startingIndex: 0)
      collectionView.reloadData()

      pendingActionsOnLayoutSubviews.append { [weak self, scrollsToBottomOnReplace] in
        guard let self else { return }
        
        if scrollsToBottomOnReplace {
          scrollTo(edge: .bottom, animated: false)
        }
      }

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
        scrollTo(edge: .bottom, animated: true)
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

  func numberOfSections(in collectionView: UICollectionView) -> Int {
    1
  }

  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    items.count
  }

  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
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

  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    // Override in subclass or use closure if needed
  }

  // MARK: - UIScrollViewDelegate

  func scrollViewDidScroll(_ scrollView: UIScrollView) {

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

    // Check if dragging into bottom safe area
    if scrollView.isDragging {
      checkDragIntoBottomSafeArea(scrollView)
    }

    notifyScrollGeometry()
  }

  func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
    hasDraggedIntoBottomSafeArea = false
  }

  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
    hasDraggedIntoBottomSafeArea = false
  }

  private func notifyScrollGeometry() {
    guard let onTiledScrollGeometryChange else { return }
    let geometry = TiledScrollGeometry(
      contentOffset: collectionView.contentOffset,
      contentSize: collectionView.contentSize,
      visibleSize: collectionView.bounds.size,
      contentInset: collectionView.adjustedContentInset
    )
    onTiledScrollGeometryChange(geometry)
  }

  private func checkDragIntoBottomSafeArea(_ scrollView: UIScrollView) {
    guard let onDragIntoBottomSafeArea else { return }

    let bottomSafeAreaHeight = tiledLayout.additionalContentInset.bottom
    guard bottomSafeAreaHeight > 0 else { return }

    let panGesture = scrollView.panGestureRecognizer
    let touchLocation = panGesture.location(in: self)
    let bottomSafeAreaTop = bounds.height - bottomSafeAreaHeight

    if touchLocation.y > bottomSafeAreaTop {
      if !hasDraggedIntoBottomSafeArea {
        hasDraggedIntoBottomSafeArea = true
        onDragIntoBottomSafeArea()
      }
    } else {
      // Reset when exiting the area, allowing re-trigger on next entry
      hasDraggedIntoBottomSafeArea = false
    }
  }

  // MARK: - Scroll Position

  func applyScrollPosition(_ position: TiledScrollPosition) {
    guard position.version > lastAppliedScrollVersion else { return }
    lastAppliedScrollVersion = position.version

    guard let edge = position.edge else { return }

    scrollTo(edge: edge, animated: position.animated)
  }
  
  private func scrollTo(edge: TiledScrollPosition.Edge, animated: Bool) {

    collectionView.layoutIfNeeded()

    // Cancel any existing animation
    springAnimator?.stop(finished: false)
    springAnimator = nil

    // Stop any existing deceleration
    collectionView.setContentOffset(collectionView.contentOffset, animated: false)

    if animated {
      let animator = SpringScrollAnimator(spring: .smooth)
      springAnimator = animator

      // Use dynamic target provider to adapt to contentInset changes mid-animation
      animator.animate(scrollView: collectionView) { scrollView in
        let inset = scrollView.adjustedContentInset
        let contentTop = -inset.top
        let contentBottom = max(
          contentTop,
          scrollView.contentSize.height - scrollView.bounds.height + inset.bottom
        )

        let target: CGFloat
        switch edge {
        case .top:
          target = contentTop
        case .bottom:
          target = contentBottom
        }

        // Stop when distance to target is minimal (already at destination)
        let shouldStop = abs(target - scrollView.contentOffset.y) < 0.5
        return SpringScrollAnimator.TargetResult(target: target, shouldStop: shouldStop)
      }
    } else {
      // Non-animated case: calculate target once and set immediately
      let inset = collectionView.adjustedContentInset
      let contentTop = -inset.top
      let contentBottom = max(
        contentTop,
        collectionView.contentSize.height - collectionView.bounds.height + inset.bottom
      )

      switch edge {
      case .top:
        collectionView.contentOffset.y = contentTop
      case .bottom:
        collectionView.contentOffset.y = contentBottom
      }
    }

    collectionView.flashScrollIndicators()
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
  func setState<Key: CustomStateKey>(
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
  func state<Key: CustomStateKey>(for itemId: Item.ID, key: Key.Type) -> Key.Value {
    stateMap[itemId]?[Key.self] ?? Key.defaultValue
  }

  /// Resets all cell states
  func resetState() {
    stateMap.removeAll()

    for cell in collectionView.visibleCells {
      if let tiledCell = cell as? TiledViewCell {
        tiledCell.customState = .empty
        tiledCell.updateContent(using: .empty)
      }
    }
  }
}

// MARK: - TiledViewRepresentable

/// UIViewRepresentable implementation for TiledView.
/// Use ``TiledView`` for the public SwiftUI interface.
struct TiledViewRepresentable<Item: Identifiable & Equatable, Cell: View>: UIViewRepresentable {

  typealias UIViewType = _TiledView<Item, Cell>

  let dataSource: ListDataSource<Item>
  let cellBuilder: (Item, CellState) -> Cell
  let cellStates: [Item.ID: CellState]?
  let onPrepend: (@MainActor () async throws -> Void)?
  let onTiledScrollGeometryChange: ((TiledScrollGeometry) -> Void)?
  let onTapBackground: (() -> Void)?
  let onDragIntoBottomSafeArea: (() -> Void)?
  let additionalContentInset: EdgeInsets
  let swiftUIWorldSafeAreaInset: EdgeInsets
  @Binding var scrollPosition: TiledScrollPosition

  init(
    dataSource: ListDataSource<Item>,
    scrollPosition: Binding<TiledScrollPosition>,
    cellStates: [Item.ID: CellState]? = nil,
    onPrepend: (@MainActor () async throws -> Void)? = nil,
    onTiledScrollGeometryChange: ((TiledScrollGeometry) -> Void)? = nil,
    onTapBackground: (() -> Void)? = nil,
    onDragIntoBottomSafeArea: (() -> Void)? = nil,
    additionalContentInset: EdgeInsets = .init(),
    swiftUIWorldSafeAreaInset: EdgeInsets = .init(),
    @ViewBuilder cellBuilder: @escaping (Item, CellState) -> Cell
  ) {
    self.dataSource = dataSource
    self._scrollPosition = scrollPosition
    self.cellStates = cellStates
    self.onPrepend = onPrepend
    self.onTiledScrollGeometryChange = onTiledScrollGeometryChange
    self.onTapBackground = onTapBackground
    self.onDragIntoBottomSafeArea = onDragIntoBottomSafeArea
    self.additionalContentInset = additionalContentInset
    self.swiftUIWorldSafeAreaInset = swiftUIWorldSafeAreaInset
    self.cellBuilder = cellBuilder
  }

  func makeUIView(context: Context) -> _TiledView<Item, Cell> {
    let view = _TiledView(cellBuilder: cellBuilder, onPrepend: onPrepend)
    updateUIView(view, context: context)
    return view
  }

  func updateUIView(_ uiView: _TiledView<Item, Cell>, context: Context) {
    
    if #available(iOS 18.0, *) {
      context.animate { 
        uiView.additionalContentInset = additionalContentInset
        uiView.swiftUIWorldSafeAreaInset = swiftUIWorldSafeAreaInset
      }
    } else {
      uiView.additionalContentInset = additionalContentInset
      uiView.swiftUIWorldSafeAreaInset = swiftUIWorldSafeAreaInset
    }
    
    uiView.autoScrollsToBottomOnAppend = scrollPosition.autoScrollsToBottomOnAppend
    uiView.scrollsToBottomOnReplace = scrollPosition.scrollsToBottomOnReplace
    uiView.onTiledScrollGeometryChange = onTiledScrollGeometryChange.map { perform in
      return { arg in
        withPrerender {
          perform(arg)
        }
      }
    }
    
    uiView.onTapBackground = onTapBackground
    uiView.onDragIntoBottomSafeArea = onDragIntoBottomSafeArea

    uiView.applyDataSource(dataSource)
    uiView.applyScrollPosition(scrollPosition)

    // Apply external cellStates if provided
    if let cellStates {
      for (id, state) in cellStates {
        uiView._setState(cellState: state, for: id)
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
///     └── TiledViewRepresentable (UIViewRepresentable)
///             └── _TiledView (UIView)
///                     ├── UICollectionView
///                     │       └── TiledViewCell (UIHostingConfiguration)
///                     └── TiledCollectionViewLayout (Custom Layout)
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
///       dataSource.replace(with: initialMessages)
///     }
///   }
/// }
/// ```
///
/// ## ListDataSource
///
/// Use ``ListDataSource`` to manage items. It tracks changes for efficient updates.
///
/// **Recommended:** Use ``ListDataSource/apply(_:)`` for most cases.
/// It automatically detects the appropriate operation.
///
/// ```swift
/// dataSource.apply([...])           // Recommended: Auto-detect changes
///
/// // Manual operations (when you know the exact change type)
/// dataSource.replace(with: [...])   // Replace all items
/// dataSource.prepend([...])         // Add to beginning (older messages)
/// dataSource.append([...])          // Add to end (newer messages)
/// dataSource.insert([...], at: 5)   // Insert at specific index
/// dataSource.updateExisting([...])  // Update existing items
/// dataSource.remove(ids: [...])     // Remove by IDs
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
/// > Warning: **Avoid using `@State` inside cell views.**
/// > TiledView uses UICollectionView with cell reuse. When cells scroll off-screen,
/// > they are recycled and any `@State` values will be reset to their initial values.
/// > Use ``CellState`` with ``CustomStateKey`` instead to persist state across cell reuse.
///
/// ## Scroll Geometry
///
/// Monitor scroll position for "scroll to bottom" buttons using ``TiledScrollGeometry``:
///
/// ```swift
/// TiledView(...)
///   .onTiledScrollGeometryChange { geometry in
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
public struct TiledView<Item: Identifiable & Equatable, Cell: View>: View {
  
  let dataSource: ListDataSource<Item>
  let cellBuilder: (Item, CellState) -> Cell
  let cellStates: [Item.ID: CellState]?
  let onPrepend: (@MainActor () async throws -> Void)?
  var onTiledScrollGeometryChange: ((TiledScrollGeometry) -> Void)?
  var onTapBackground: (() -> Void)?
  var onDragIntoBottomSafeArea: (() -> Void)?
  var additionalContentInset: EdgeInsets = .init()
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

  public var body: some View {
    GeometryReader { proxy in
      TiledViewRepresentable(
        dataSource: dataSource,
        scrollPosition: $scrollPosition,
        cellStates: cellStates,
        onPrepend: onPrepend,
        onTiledScrollGeometryChange: onTiledScrollGeometryChange,
        onTapBackground: onTapBackground,
        onDragIntoBottomSafeArea: onDragIntoBottomSafeArea,
        additionalContentInset: additionalContentInset,
        swiftUIWorldSafeAreaInset: proxy.safeAreaInsets,
        cellBuilder: cellBuilder
      )
      .ignoresSafeArea()
    }
  }

  public consuming func onTiledScrollGeometryChange(
    _ action: @escaping (TiledScrollGeometry) -> Void
  ) -> Self {
    self.onTiledScrollGeometryChange = action
    return self
  }

  /// Sets additional content inset for keyboard, headers, footers, etc.
  ///
  /// Use this to add extra scrollable space at the edges of the content.
  /// For keyboard handling, set the bottom inset to the keyboard height.
  ///
  /// ```swift
  /// TiledView(...)
  ///   .additionalContentInset(EdgeInsets(top: 0, leading: 0, bottom: keyboardHeight, trailing: 0))
  /// ```
  public consuming func additionalContentInset(
    _ inset: EdgeInsets
  ) -> Self {
    self.additionalContentInset = inset
    return self
  }

  /// Sets a callback for when the background (empty area) is tapped.
  ///
  /// Use this to dismiss the keyboard when tapping outside of cells.
  ///
  /// ```swift
  /// TiledView(...)
  ///   .onTapBackground {
  ///     UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
  ///   }
  /// ```
  public consuming func onTapBackground(
    _ action: @escaping () -> Void
  ) -> Self {
    self.onTapBackground = action
    return self
  }

  /// Sets a callback for when dragging into the bottom safe area.
  ///
  /// Use this to dismiss the keyboard when the user drags into the bottom safe area
  /// (the region covered by `safeAreaInsets.bottom`, typically the keyboard).
  ///
  /// ```swift
  /// TiledView(...)
  ///   .onDragIntoBottomSafeArea {
  ///     UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
  ///   }
  /// ```
  public consuming func onDragIntoBottomSafeArea(
    _ action: @escaping () -> Void
  ) -> Self {
    self.onDragIntoBottomSafeArea = action
    return self
  }
}
