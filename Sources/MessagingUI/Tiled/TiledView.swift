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

// MARK: - EdgeLoadTrigger

/// Encapsulates state for edge-triggered loading (prepend/append).
private struct EdgeLoadTrigger<Indicator: View>: ~Copyable {

  /// Whether the trigger has been activated
  var isTriggered: Bool = false

  /// Distance from edge to trigger loading
  let threshold: CGFloat

  /// Currently running load task
  var task: Task<Void, Never>?

  /// Loader configuration
  var loader: Loader<Indicator>?

  init(threshold: CGFloat = 100) {
    self.threshold = threshold
  }

  /// Whether loading is in progress
  var isLoading: Bool {
    guard let loader else { return false }
    if let isProcessing = loader.isProcessing {
      return isProcessing  // sync mode: use external state
    }
    return task != nil  // async mode: task is running
  }
}

/// MARK: - RevealGestureState

/// Encapsulates state for swipe-to-reveal gesture handling.
private struct RevealGestureState: ~Copyable {

  /// Pan gesture recognizer for horizontal swipe-to-reveal
  var panGesture: UIPanGestureRecognizer?

  /// Minimum movement in points before determining gesture direction
  let directionThreshold: CGFloat = 10

  /// Whether the gesture direction has been determined
  var isDirectionDetermined = false

  /// Whether the current gesture is recognized as a reveal gesture (horizontal swipe)
  var isActive = false

  /// Resets the gesture state for a new gesture
  mutating func reset() {
    isDirectionDetermined = false
    isActive = false
  }
}

// MARK: - Loader

/// Configuration for edge loading with indicator view.
///
/// Use this to configure prepend/append loading behavior with a visual indicator.
///
/// Two modes are supported:
/// - **Async mode**: Loading state is auto-managed internally
/// - **Sync mode**: Loading state is provided externally via `isProcessing`
///
/// ```swift
/// // Async mode (auto-managed loading state)
/// TiledView(
///   dataSource: dataSource,
///   scrollPosition: $scrollPosition,
///   prependLoader: .loader(perform: {
///     await store.loadOlder()
///   }) {
///     ProgressView()
///   }
/// )
///
/// // Sync mode (manual loading state)
/// TiledView(
///   ...
///   prependLoader: .loader(
///     perform: { store.loadOlder() },
///     isProcessing: store.isPrependLoading
///   ) {
///     ProgressView()
///   }
/// )
/// ```
public struct Loader<Indicator: View> {

  enum PerformAction: Sendable {
    case async(@Sendable @MainActor () async -> Void)
    case sync(@Sendable @MainActor () -> Void)
  }

  let perform: PerformAction
  /// nil means auto-managed (async mode), non-nil means externally provided (sync mode)
  let isProcessing: Bool?
  let indicator: Indicator

  /// Creates a loader with async perform action (auto-managed loading state).
  ///
  /// The loading state is automatically managed internally - it becomes true when
  /// perform starts and false when it completes.
  ///
  /// - Parameters:
  ///   - perform: Async action to execute when edge is reached
  ///   - indicator: View to display while loading
  public static func loader(
    perform: @escaping @Sendable @MainActor () async -> Void,
    @ViewBuilder indicator: () -> Indicator
  ) -> Self {
    Loader(perform: .async(perform), isProcessing: nil, indicator: indicator())
  }

  /// Creates a loader with sync perform action and external loading state.
  ///
  /// Use this when you manage loading state externally (e.g., in your store/viewmodel).
  ///
  /// - Parameters:
  ///   - perform: Sync action to execute when edge is reached
  ///   - isProcessing: External loading state binding
  ///   - indicator: View to display while loading
  public static func loader(
    perform: @escaping @Sendable @MainActor () -> Void,
    isProcessing: Bool,
    @ViewBuilder indicator: () -> Indicator
  ) -> Self {
    Loader(perform: .sync(perform), isProcessing: isProcessing, indicator: indicator())
  }
}

extension Optional where Wrapped == Loader<Never> {
  /// A disabled loader that does nothing.
  ///
  /// Use this when you need to specify a loader parameter but don't want any loading behavior.
  /// ```swift
  /// TiledView(
  ///   dataSource: dataSource,
  ///   scrollPosition: $scrollPosition,
  ///   prependLoader: .loader(perform: { ... }) { ... },
  ///   appendLoader: .disabled  // No append loading
  /// ) { ... }
  /// ```
  public static var disabled: Loader<Never>? { nil }
}

// MARK: - TypingIndicator

/// Configuration for displaying a typing indicator at the bottom of the message list.
///
/// Use this to show when other users are typing in a chat conversation.
/// The indicator appears below the last message and above the append loader.
///
/// ```swift
/// TiledView(
///   dataSource: dataSource,
///   scrollPosition: $scrollPosition,
///   typingIndicator: .indicator(isVisible: store.isTyping) {
///     TypingBubbleView(users: store.typingUsers)
///   }
/// ) { message, state in
///   MessageBubbleView(message: message)
/// }
/// ```
public struct TypingIndicator<Content: View> {

  /// Whether the typing indicator should be visible
  let isVisible: Bool

  /// The view to display as the typing indicator
  let content: Content

  /// Creates a typing indicator configuration.
  ///
  /// - Parameters:
  ///   - isVisible: Whether to show the indicator
  ///   - content: The indicator view (e.g., animated dots bubble)
  public static func indicator(
    isVisible: Bool,
    @ViewBuilder content: () -> Content
  ) -> Self {
    TypingIndicator(isVisible: isVisible, content: content())
  }
}

extension Optional where Wrapped == TypingIndicator<Never> {
  /// A disabled typing indicator that never shows.
  ///
  /// Use this when you need to specify a typingIndicator parameter but don't want the feature.
  /// ```swift
  /// TiledView(
  ///   dataSource: dataSource,
  ///   scrollPosition: $scrollPosition,
  ///   typingIndicator: .disabled
  /// ) { ... }
  /// ```
  public static var disabled: TypingIndicator<Never>? { nil }
}

// MARK: - _TiledView

final class _TiledView<
  Item: Identifiable & Equatable,
  Cell: View,
  PrependLoadingView: View,
  AppendLoadingView: View,
  TypingIndicatorView: View
>: UIView, UICollectionViewDataSource, UICollectionViewDelegate, UIGestureRecognizerDelegate {

  private let tiledLayout: TiledCollectionViewLayout = .init()
  private var collectionView: UICollectionView!

  private var items: Deque<Item> = []
  private let cellBuilder: (Item, CellState) -> Cell

  /// prototype cell for size measurement
  private let sizingCell = TiledViewCell()

  /// DataSource tracking
  private var lastDataSourceID: UUID?
  private var appliedCursor: Int = 0

  /// Edge load triggers
  private var prependTrigger = EdgeLoadTrigger<PrependLoadingView>()
  private var appendTrigger = EdgeLoadTrigger<AppendLoadingView>()

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

  // MARK: - Reveal Offset (Swipe-to-Reveal)

  /// Shared observable state for reveal offset
  let cellReveal = CellReveal()

  /// Configuration for reveal gesture
  var revealConfiguration: RevealConfiguration = .default

  /// Sets the reveal offset, updating observable state.
  private func setRevealOffset(_ newValue: CGFloat) {
    guard cellReveal.offset != newValue else { return }
    cellReveal.offset = newValue
  }

  /// State for swipe-to-reveal gesture handling
  private var revealGestureState = RevealGestureState()

  // MARK: - Loading

  /// Sets loaders and updates visibility if loading states changed.
  func setLoaders(
    prepend: Loader<PrependLoadingView>?,
    append: Loader<AppendLoadingView>?
  ) {
    let oldPrependLoading = prependTrigger.isLoading
    let oldAppendLoading = appendTrigger.isLoading

    prependTrigger.loader = prepend
    appendTrigger.loader = append

    let newPrependLoading = prependTrigger.isLoading
    let newAppendLoading = appendTrigger.isLoading

    guard oldPrependLoading != newPrependLoading || oldAppendLoading != newAppendLoading else {
      return
    }

    updateLoadingIndicatorVisibility()
  }

  // MARK: - Typing Indicator

  /// Current typing indicator configuration
  private var typingIndicator: TypingIndicator<TypingIndicatorView>?

  /// Sets the typing indicator and updates visibility.
  func setTypingIndicator(_ indicator: TypingIndicator<TypingIndicatorView>?) {
    let wasVisible = typingIndicator?.isVisible == true
    typingIndicator = indicator
    let isVisible = indicator?.isVisible == true

    guard wasVisible != isVisible else { return }
    updateTypingIndicatorVisibility()
  }

  /// Prototype view for measuring loading indicator size
  private let sizingLoadingIndicator = TiledLoadingIndicatorView()

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
    // With .never, adjustedContentInset = contentInset (no automatic safeArea addition)
    // So we directly use our desired insets without subtracting safeAreaInsets
    let uiEdgeInsets = combined.toUIEdgeInsets(layoutDirection: effectiveUserInterfaceLayoutDirection)
    // Calculate delta before applying changes
    // Delta = new additionalContentInset.bottom - old additionalContentInset.bottom
    let oldAdditionalBottom = tiledLayout.additionalContentInset.bottom
    let deltaBottom = uiEdgeInsets.bottom - oldAdditionalBottom

    guard deltaBottom != 0 else {
      // Just apply without animation if no change
      tiledLayout.additionalContentInset = uiEdgeInsets
      // With .never, scroll indicators need manual safe area adjustment
      collectionView.verticalScrollIndicatorInsets.top = uiEdgeInsets.top
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
      // With .never, scroll indicators need manual safe area adjustment
      self.collectionView.verticalScrollIndicatorInsets.top = uiEdgeInsets.top
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

  init(
    cellBuilder: @escaping (Item, CellState) -> Cell
  ) {
    self.cellBuilder = cellBuilder
    super.init(frame: .zero)

    do {
      tiledLayout.itemSizeProvider = { [weak self] index, width in
        self?.measureSize(at: index, width: width)
      }
      
      collectionView = .init(frame: .zero, collectionViewLayout: tiledLayout)
      collectionView.translatesAutoresizingMaskIntoConstraints = false
      collectionView.selfSizingInvalidation = .enabledIncludingConstraints
      collectionView.backgroundColor = .clear
      collectionView.allowsSelection = false
      collectionView.dataSource = self
      collectionView.delegate = self
      collectionView.alwaysBounceVertical = true
      /// It have to use `.always` as scrolling won't work correctly with `.never`.
      collectionView.contentInsetAdjustmentBehavior = .never
      collectionView.automaticallyAdjustsScrollIndicatorInsets = false
      collectionView.isPrefetchingEnabled = false
      
      collectionView.register(TiledViewCell.self, forCellWithReuseIdentifier: TiledViewCell.reuseIdentifier)

      // Register supplementary views for loading indicators and typing indicator
      collectionView.register(
        TiledLoadingIndicatorView.self,
        forSupplementaryViewOfKind: TiledLoadingIndicatorView.headerKind,
        withReuseIdentifier: TiledLoadingIndicatorView.reuseIdentifier
      )
      collectionView.register(
        TiledLoadingIndicatorView.self,
        forSupplementaryViewOfKind: TiledLoadingIndicatorView.footerKind,
        withReuseIdentifier: TiledLoadingIndicatorView.reuseIdentifier
      )
      collectionView.register(
        TiledLoadingIndicatorView.self,
        forSupplementaryViewOfKind: TiledLoadingIndicatorView.typingIndicatorKind,
        withReuseIdentifier: TiledLoadingIndicatorView.reuseIdentifier
      )

      let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapBackground(_:)))
      tapGesture.cancelsTouchesInView = false
      collectionView.addGestureRecognizer(tapGesture)

      // Setup reveal pan gesture for horizontal swipe-to-reveal
      let revealGesture = UIPanGestureRecognizer(target: self, action: #selector(handleRevealPanGesture(_:)))
      revealGesture.delegate = self
      collectionView.addGestureRecognizer(revealGesture)
      revealGestureState.panGesture = revealGesture

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
    sizingCell.configure(with: cellBuilder(item, state), cellReveal: cellReveal)
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

      let indexPaths = (0..<newItems.count).map { IndexPath(item: $0, section: 0) }

      UIView.performWithoutAnimation {
        collectionView.performBatchUpdates({
          collectionView.insertItems(at: indexPaths)
        }, completion: nil)
      }

    case .append(let ids):
      let startingIndex = items.count
      let newItems = ids.compactMap { id in dataSource.items.first { $0.id == id } }
      items.append(contentsOf: newItems)
      tiledLayout.appendItems(count: newItems.count, startingIndex: startingIndex)

      let indexPaths = (startingIndex..<startingIndex + newItems.count).map {
        IndexPath(item: $0, section: 0)
      }

      UIView.performWithoutAnimation {
        collectionView.performBatchUpdates({
          collectionView.insertItems(at: indexPaths)
        }, completion: nil)
      }

      if autoScrollsToBottomOnAppend {
        scrollTo(edge: .bottom, animated: true)
      }

    case .insert(let index, let ids):
      let newItems = ids.compactMap { id in dataSource.items.first { $0.id == id } }
      for (offset, item) in newItems.enumerated() {
        items.insert(item, at: index + offset)
      }
      tiledLayout.insertItems(count: newItems.count, at: index)

      let indexPaths = (index..<index + newItems.count).map {
        IndexPath(item: $0, section: 0)
      }

      UIView.performWithoutAnimation {
        collectionView.performBatchUpdates({
          collectionView.insertItems(at: indexPaths)
        }, completion: nil)
      }

    case .update(let ids):
      for id in ids {
        if let index = items.firstIndex(where: { $0.id == id }),
           let newItem = dataSource.items.first(where: { $0.id == id }) {
          items[index] = newItem
        }
      }

      let indexPaths = ids.compactMap { id -> IndexPath? in
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return IndexPath(item: index, section: 0)
      }

      guard !indexPaths.isEmpty else { return }

      UIView.performWithoutAnimation {
        collectionView.performBatchUpdates({
          collectionView.reloadItems(at: indexPaths)
        }, completion: nil)
      }

    case .remove(let ids):
      let idsSet = Set(ids)
      // Find indices before removing items
      let indicesToRemove = items.enumerated()
        .filter { idsSet.contains($0.element.id) }
        .map { $0.offset }
      items.removeAll { idsSet.contains($0.id) }
      tiledLayout.removeItems(at: indicesToRemove)

      let indexPaths = indicesToRemove.map { IndexPath(item: $0, section: 0) }

      UIView.performWithoutAnimation {
        collectionView.performBatchUpdates({
          collectionView.deleteItems(at: indexPaths)
        }, completion: nil)
      }
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

    cell.configure(with: cellBuilder(item, state), cellReveal: cellReveal)
    cell.customState = state
    cell._updateConfigurationHandler = { [weak self] cell, newState in
      guard let self else { return }
      cell.configure(with: self.cellBuilder(item, newState), cellReveal: self.cellReveal)
    }

    return cell
  }

  func collectionView(
    _ collectionView: UICollectionView,
    viewForSupplementaryElementOfKind kind: String,
    at indexPath: IndexPath
  ) -> UICollectionReusableView {
    let view = collectionView.dequeueReusableSupplementaryView(
      ofKind: kind,
      withReuseIdentifier: TiledLoadingIndicatorView.reuseIdentifier,
      for: indexPath
    ) as! TiledLoadingIndicatorView

    switch kind {
    case TiledLoadingIndicatorView.headerKind:
      if let loader = prependTrigger.loader {
        view.configure(with: loader.indicator)
      }
    case TiledLoadingIndicatorView.typingIndicatorKind:
      if let indicator = typingIndicator, indicator.isVisible {
        view.configure(with: indicator.content)
      }
    case TiledLoadingIndicatorView.footerKind:
      if let loader = appendTrigger.loader {
        view.configure(with: loader.indicator)
      }
    default:
      break
    }

    return view
  }

  // MARK: UICollectionViewDelegate

  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    // Override in subclass or use closure if needed
  }

  // MARK: - UIScrollViewDelegate

  func scrollViewDidScroll(_ scrollView: UIScrollView) {

    // Prepend trigger
    let offsetY = scrollView.contentOffset.y + scrollView.contentInset.top
    if offsetY <= prependTrigger.threshold {
      if !prependTrigger.isTriggered && !prependTrigger.isLoading {
        prependTrigger.isTriggered = true
        triggerPrependLoad()
      }
    } else {
      prependTrigger.isTriggered = false
    }

    // Append trigger
    let maxOffsetY = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
    let distanceFromBottom = max(0, maxOffsetY - scrollView.contentOffset.y)
    if distanceFromBottom <= appendTrigger.threshold {
      if !appendTrigger.isTriggered && !appendTrigger.isLoading {
        appendTrigger.isTriggered = true
        triggerAppendLoad()
      }
    } else {
      appendTrigger.isTriggered = false
    }

    // Check if dragging into bottom safe area
    if scrollView.isTracking && scrollView.isDragging {
      checkDragIntoBottomSafeArea(scrollView)
    }

    notifyScrollGeometry()
  }

  private func triggerPrependLoad() {
    guard let loader = prependTrigger.loader else { return }

    switch loader.perform {
    case .async(let perform):
      // task != nil indicates loading state
      prependTrigger.task = Task { @MainActor [weak self] in
        defer {
          self?.prependTrigger.task = nil
          self?.updateLoadingIndicatorVisibility()
        }
        self?.updateLoadingIndicatorVisibility()
        await perform()
      }
    case .sync(let perform):
      // External loading state management via isProcessing
      perform()
    }
  }

  private func triggerAppendLoad() {
    guard let loader = appendTrigger.loader else { return }

    switch loader.perform {
    case .async(let perform):
      // task != nil indicates loading state
      appendTrigger.task = Task { @MainActor [weak self] in
        defer {
          self?.appendTrigger.task = nil
          self?.updateLoadingIndicatorVisibility()
        }
        self?.updateLoadingIndicatorVisibility()
        await perform()
      }
    case .sync(let perform):
      // External loading state management via isProcessing
      perform()
    }
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

  // MARK: - Reveal Offset (Swipe-to-Reveal)

  /// Handles the dedicated pan gesture for horizontal swipe-to-reveal.
  @objc private func handleRevealPanGesture(_ gesture: UIPanGestureRecognizer) {
    guard revealConfiguration.isEnabled else { return }

    switch gesture.state {
    case .began:
      revealGestureState.reset()

    case .changed:
      let translation = gesture.translation(in: gesture.view)

      // Determine gesture direction if not yet determined
      if !revealGestureState.isDirectionDetermined {
        let totalMovement = abs(translation.x) + abs(translation.y)

        // Wait until we have enough movement to determine direction
        if totalMovement < revealGestureState.directionThreshold {
          return
        }

        revealGestureState.isDirectionDetermined = true

        // Check if gesture is predominantly horizontal left swipe
        // Horizontal movement must be greater than vertical movement
        if abs(translation.x) > abs(translation.y) && translation.x < 0 {
          revealGestureState.isActive = true
        } else {
          // This is a vertical scroll or right swipe, ignore for reveal
          revealGestureState.isActive = false
          return
        }
      }

      // If not a reveal gesture, ignore
      guard revealGestureState.isActive else { return }

      // Convert left swipe (negative x) to positive rawOffset
      let rawOffset = -translation.x

      // Subtract direction threshold so movement starts at 0
      let adjustedOffset = rawOffset - revealGestureState.directionThreshold
      setRevealOffset(max(0, adjustedOffset))

    case .ended, .cancelled:
      snapBackReveal()
      revealGestureState.reset()

    default:
      break
    }
  }

  // MARK: - UIGestureRecognizerDelegate

  /// Allow simultaneous recognition with scroll view's pan gesture.
  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    // Allow reveal gesture to work with scroll view
    if gestureRecognizer == revealGestureState.panGesture {
      return true
    }
    return false
  }

  /// Animates reveal offset back to zero with spring animation.
  private func snapBackReveal() {
    withAnimation(.snappy) {
      setRevealOffset(0)
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

  // MARK: - Loading Indicator Management

  private func updateLoadingIndicatorVisibility() {
    guard collectionView != nil else { return }

    let boundsWidth = bounds.width

    // Measure header size
    let headerHeight: CGFloat
    if prependTrigger.isLoading, let loader = prependTrigger.loader {
      headerHeight = measureLoadingIndicatorSize(loader.indicator, width: boundsWidth).height
    } else {
      headerHeight = 0
    }

    // Measure footer size
    let footerHeight: CGFloat
    if appendTrigger.isLoading, let loader = appendTrigger.loader {
      footerHeight = measureLoadingIndicatorSize(loader.indicator, width: boundsWidth).height
    } else {
      footerHeight = 0
    }

    // Update layout
    tiledLayout.headerSize = CGSize(width: boundsWidth, height: headerHeight)
    tiledLayout.footerSize = CGSize(width: boundsWidth, height: footerHeight)
    tiledLayout.invalidateLayout()
  }

  private func updateTypingIndicatorVisibility() {
    guard collectionView != nil else { return }

    let boundsWidth = bounds.width
    let oldHeight = tiledLayout.typingIndicatorSize.height

    // Measure typing indicator size
    let typingHeight: CGFloat
    if let indicator = typingIndicator, indicator.isVisible {
      typingHeight = measureLoadingIndicatorSize(indicator.content, width: boundsWidth).height
    } else {
      typingHeight = 0
    }

    let heightDiff = typingHeight - oldHeight

    // Update layout
    tiledLayout.typingIndicatorSize = CGSize(width: boundsWidth, height: typingHeight)
    tiledLayout.invalidateLayout()

    // Adjust scroll position to keep content stable when typing indicator appears/disappears
    if heightDiff != 0 {
      // Check if user is near bottom (within threshold)
      let maxOffsetY = collectionView.contentSize.height - collectionView.bounds.height + collectionView.adjustedContentInset.bottom
      let distanceFromBottom = max(0, maxOffsetY - collectionView.contentOffset.y)
      let isNearBottom = distanceFromBottom < 100

      if isNearBottom {
        // Auto-scroll to keep bottom visible when typing indicator appears
        var newOffset = collectionView.contentOffset
        newOffset.y += heightDiff
        collectionView.setContentOffset(newOffset, animated: true)
      }
    }
  }

  private func measureLoadingIndicatorSize<V: View>(_ view: V, width: CGFloat) -> CGSize {
    sizingLoadingIndicator.configure(with: view)
    sizingLoadingIndicator.bounds.size.width = width
    sizingLoadingIndicator.layoutIfNeeded()

    let targetSize = CGSize(
      width: width,
      height: UIView.layoutFittingCompressedSize.height
    )

    let size = sizingLoadingIndicator.systemLayoutSizeFitting(
      targetSize,
      withHorizontalFittingPriority: .required,
      verticalFittingPriority: .fittingSizeLevel
    )

    return size
  }
}

// MARK: - TiledViewRepresentable

/// UIViewRepresentable implementation for TiledView.
/// Use ``TiledView`` for the public SwiftUI interface.
struct TiledViewRepresentable<
  Item: Identifiable & Equatable,
  Cell: View,
  PrependLoadingView: View,
  AppendLoadingView: View,
  TypingIndicatorContent: View
>: UIViewRepresentable {

  typealias UIViewType = _TiledView<Item, Cell, PrependLoadingView, AppendLoadingView, TypingIndicatorContent>

  let dataSource: ListDataSource<Item>
  let cellBuilder: (Item, CellState) -> Cell
  let cellStates: [Item.ID: CellState]?
  let onTiledScrollGeometryChange: ((TiledScrollGeometry) -> Void)?
  let onTapBackground: (() -> Void)?
  let onDragIntoBottomSafeArea: (() -> Void)?
  let additionalContentInset: EdgeInsets
  let swiftUIWorldSafeAreaInset: EdgeInsets
  let revealConfiguration: RevealConfiguration
  let prependLoader: Loader<PrependLoadingView>?
  let appendLoader: Loader<AppendLoadingView>?
  let typingIndicator: TypingIndicator<TypingIndicatorContent>?
  @Binding var scrollPosition: TiledScrollPosition

  init(
    dataSource: ListDataSource<Item>,
    scrollPosition: Binding<TiledScrollPosition>,
    cellStates: [Item.ID: CellState]? = nil,
    onTiledScrollGeometryChange: ((TiledScrollGeometry) -> Void)? = nil,
    onTapBackground: (() -> Void)? = nil,
    onDragIntoBottomSafeArea: (() -> Void)? = nil,
    additionalContentInset: EdgeInsets = .init(),
    swiftUIWorldSafeAreaInset: EdgeInsets = .init(),
    revealConfiguration: RevealConfiguration = .default,
    prependLoader: Loader<PrependLoadingView>?,
    appendLoader: Loader<AppendLoadingView>?,
    typingIndicator: TypingIndicator<TypingIndicatorContent>?,
    @ViewBuilder cellBuilder: @escaping (Item, CellState) -> Cell
  ) {
    self.dataSource = dataSource
    self._scrollPosition = scrollPosition
    self.cellStates = cellStates
    self.onTiledScrollGeometryChange = onTiledScrollGeometryChange
    self.onTapBackground = onTapBackground
    self.onDragIntoBottomSafeArea = onDragIntoBottomSafeArea
    self.additionalContentInset = additionalContentInset
    self.swiftUIWorldSafeAreaInset = swiftUIWorldSafeAreaInset
    self.revealConfiguration = revealConfiguration
    self.prependLoader = prependLoader
    self.appendLoader = appendLoader
    self.typingIndicator = typingIndicator
    self.cellBuilder = cellBuilder
  }

  func makeUIView(context: Context) -> UIViewType {
    let view = UIViewType(cellBuilder: cellBuilder)
    updateUIView(view, context: context)
    return view
  }

  func updateUIView(_ uiView: UIViewType, context: Context) {

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
    uiView.revealConfiguration = revealConfiguration

    // Update loaders and typing indicator
    uiView.setLoaders(prepend: prependLoader, append: appendLoader)
    uiView.setTypingIndicator(typingIndicator)

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
public struct TiledView<
  Item: Identifiable & Equatable,
  Cell: View,
  PrependLoadingView: View,
  AppendLoadingView: View,
  TypingIndicatorContent: View
>: View {

  let dataSource: ListDataSource<Item>
  let cellBuilder: (Item, CellState) -> Cell
  let cellStates: [Item.ID: CellState]?
  var onTiledScrollGeometryChange: ((TiledScrollGeometry) -> Void)?
  var onTapBackground: (() -> Void)?
  var onDragIntoBottomSafeArea: (() -> Void)?
  var additionalContentInset: EdgeInsets = .init()
  var revealConfiguration: RevealConfiguration = .default
  let prependLoader: Loader<PrependLoadingView>?
  let appendLoader: Loader<AppendLoadingView>?
  let typingIndicator: TypingIndicator<TypingIndicatorContent>?
  @Binding var scrollPosition: TiledScrollPosition

  /// Internal initializer for creating TiledView with all parameters (used by modifiers)
  init(
    dataSource: ListDataSource<Item>,
    cellBuilder: @escaping (Item, CellState) -> Cell,
    cellStates: [Item.ID: CellState]?,
    onTiledScrollGeometryChange: ((TiledScrollGeometry) -> Void)?,
    onTapBackground: (() -> Void)?,
    onDragIntoBottomSafeArea: (() -> Void)?,
    additionalContentInset: EdgeInsets,
    revealConfiguration: RevealConfiguration,
    prependLoader: Loader<PrependLoadingView>?,
    appendLoader: Loader<AppendLoadingView>?,
    typingIndicator: TypingIndicator<TypingIndicatorContent>?,
    scrollPosition: Binding<TiledScrollPosition>
  ) {
    self.dataSource = dataSource
    self.cellBuilder = cellBuilder
    self.cellStates = cellStates
    self.onTiledScrollGeometryChange = onTiledScrollGeometryChange
    self.onTapBackground = onTapBackground
    self.onDragIntoBottomSafeArea = onDragIntoBottomSafeArea
    self.additionalContentInset = additionalContentInset
    self.revealConfiguration = revealConfiguration
    self.prependLoader = prependLoader
    self.appendLoader = appendLoader
    self.typingIndicator = typingIndicator
    self._scrollPosition = scrollPosition
  }
}

// MARK: - Init without loaders

extension TiledView where PrependLoadingView == Never, AppendLoadingView == Never, TypingIndicatorContent == Never {

  /// Creates a TiledView without loaders or typing indicator.
  ///
  /// ```swift
  /// TiledView(dataSource: dataSource, scrollPosition: $scrollPosition) { message, state in
  ///   MessageBubbleCell(item: message)
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - dataSource: The data source containing items to display.
  ///   - scrollPosition: Binding to control scroll position.
  ///   - cellStates: Optional per-cell state storage.
  ///   - cellBuilder: A closure that returns a `TiledCellContent` for each item.
  public init<CellContent: TiledCellContent>(
    dataSource: ListDataSource<Item>,
    scrollPosition: Binding<TiledScrollPosition>,
    cellStates: [Item.ID: CellState]? = nil,
    cellBuilder: @escaping (Item, CellState) -> CellContent
  ) where Cell == TiledCellContentWrapper<CellContent> {
    self.dataSource = dataSource
    self._scrollPosition = scrollPosition
    self.cellStates = cellStates
    self.prependLoader = nil
    self.appendLoader = nil
    self.typingIndicator = nil
    self.cellBuilder = { item, state in
      TiledCellContentWrapper(content: cellBuilder(item, state))
    }
  }
}

// MARK: - Init with loaders

extension TiledView where TypingIndicatorContent == Never {

  /// Creates a TiledView with prepend and/or append loaders.
  ///
  /// Use this initializer when you need infinite scrolling with loading indicators.
  ///
  /// ```swift
  /// TiledView(
  ///   dataSource: dataSource,
  ///   scrollPosition: $scrollPosition,
  ///   prependLoader: .loader(perform: {
  ///     await store.loadOlder()
  ///   }) {
  ///     ProgressView()
  ///   },
  ///   appendLoader: .loader(perform: {
  ///     await store.loadNewer()
  ///   }) {
  ///     ProgressView()
  ///   }
  /// ) { message, state in
  ///   MessageBubbleView(message: message)
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - dataSource: The data source containing items to display.
  ///   - scrollPosition: Binding to control scroll position.
  ///   - cellStates: Optional per-cell state storage.
  ///   - prependLoader: Optional loader for prepend/load-older operations.
  ///   - appendLoader: Optional loader for append/load-newer operations.
  ///   - cellBuilder: A closure that returns a `TiledCellContent` for each item.
  public init<CellContent: TiledCellContent>(
    dataSource: ListDataSource<Item>,
    scrollPosition: Binding<TiledScrollPosition>,
    cellStates: [Item.ID: CellState]? = nil,
    prependLoader: Loader<PrependLoadingView>?,
    appendLoader: Loader<AppendLoadingView>?,
    cellBuilder: @escaping (Item, CellState) -> CellContent
  ) where Cell == TiledCellContentWrapper<CellContent> {
    self.dataSource = dataSource
    self._scrollPosition = scrollPosition
    self.cellStates = cellStates
    self.prependLoader = prependLoader
    self.appendLoader = appendLoader
    self.typingIndicator = nil
    self.cellBuilder = { item, state in
      TiledCellContentWrapper(content: cellBuilder(item, state))
    }
  }
}

// MARK: - Init with loaders and typing indicator

extension TiledView {

  /// Creates a TiledView with prepend/append loaders and a typing indicator.
  ///
  /// Use this initializer when you need infinite scrolling with loading indicators
  /// and a typing indicator for showing when other users are typing.
  ///
  /// ```swift
  /// TiledView(
  ///   dataSource: dataSource,
  ///   scrollPosition: $scrollPosition,
  ///   prependLoader: .loader(perform: { await store.loadOlder() }) { ProgressView() },
  ///   appendLoader: .disabled,
  ///   typingIndicator: .indicator(isVisible: store.isTyping) {
  ///     TypingBubbleView(users: store.typingUsers)
  ///   }
  /// ) { message, state in
  ///   MessageBubbleView(message: message)
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - dataSource: The data source containing items to display.
  ///   - scrollPosition: Binding to control scroll position.
  ///   - cellStates: Optional per-cell state storage.
  ///   - prependLoader: Optional loader for prepend/load-older operations.
  ///   - appendLoader: Optional loader for append/load-newer operations.
  ///   - typingIndicator: Optional typing indicator configuration.
  ///   - cellBuilder: A closure that returns a `TiledCellContent` for each item.
  public init<CellContent: TiledCellContent>(
    dataSource: ListDataSource<Item>,
    scrollPosition: Binding<TiledScrollPosition>,
    cellStates: [Item.ID: CellState]? = nil,
    prependLoader: Loader<PrependLoadingView>?,
    appendLoader: Loader<AppendLoadingView>?,
    typingIndicator: TypingIndicator<TypingIndicatorContent>?,
    cellBuilder: @escaping (Item, CellState) -> CellContent
  ) where Cell == TiledCellContentWrapper<CellContent> {
    self.dataSource = dataSource
    self._scrollPosition = scrollPosition
    self.cellStates = cellStates
    self.prependLoader = prependLoader
    self.appendLoader = appendLoader
    self.typingIndicator = typingIndicator
    self.cellBuilder = { item, state in
      TiledCellContentWrapper(content: cellBuilder(item, state))
    }
  }
}

// MARK: - Init with prependLoader only (appendLoader disabled by default)

extension TiledView where AppendLoadingView == Never, TypingIndicatorContent == Never {

  /// Creates a TiledView with prepend loader only.
  ///
  /// Use this when you only need to load older items (prepend).
  /// The appendLoader defaults to `.disabled`.
  ///
  /// ```swift
  /// TiledView(
  ///   dataSource: dataSource,
  ///   scrollPosition: $scrollPosition,
  ///   prependLoader: .loader(perform: { await store.loadOlder() }) {
  ///     ProgressView()
  ///   }
  /// ) { message, state in
  ///   MessageBubbleView(message: message)
  /// }
  /// ```
  public init<CellContent: TiledCellContent>(
    dataSource: ListDataSource<Item>,
    scrollPosition: Binding<TiledScrollPosition>,
    cellStates: [Item.ID: CellState]? = nil,
    prependLoader: Loader<PrependLoadingView>?,
    appendLoader: Loader<Never>? = .disabled,
    cellBuilder: @escaping (Item, CellState) -> CellContent
  ) where Cell == TiledCellContentWrapper<CellContent> {
    self.dataSource = dataSource
    self._scrollPosition = scrollPosition
    self.cellStates = cellStates
    self.prependLoader = prependLoader
    self.appendLoader = appendLoader
    self.typingIndicator = nil
    self.cellBuilder = { item, state in
      TiledCellContentWrapper(content: cellBuilder(item, state))
    }
  }
}

// MARK: - Init with appendLoader only (prependLoader disabled by default)

extension TiledView where PrependLoadingView == Never, TypingIndicatorContent == Never {

  /// Creates a TiledView with append loader only.
  ///
  /// Use this when you only need to load newer items (append).
  /// The prependLoader defaults to `.disabled`.
  ///
  /// ```swift
  /// TiledView(
  ///   dataSource: dataSource,
  ///   scrollPosition: $scrollPosition,
  ///   appendLoader: .loader(perform: { await store.loadNewer() }) {
  ///     ProgressView()
  ///   }
  /// ) { message, state in
  ///   MessageBubbleView(message: message)
  /// }
  /// ```
  public init<CellContent: TiledCellContent>(
    dataSource: ListDataSource<Item>,
    scrollPosition: Binding<TiledScrollPosition>,
    cellStates: [Item.ID: CellState]? = nil,
    prependLoader: Loader<Never>? = .disabled,
    appendLoader: Loader<AppendLoadingView>?,
    cellBuilder: @escaping (Item, CellState) -> CellContent
  ) where Cell == TiledCellContentWrapper<CellContent> {
    self.dataSource = dataSource
    self._scrollPosition = scrollPosition
    self.cellStates = cellStates
    self.prependLoader = prependLoader
    self.appendLoader = appendLoader
    self.typingIndicator = nil
    self.cellBuilder = { item, state in
      TiledCellContentWrapper(content: cellBuilder(item, state))
    }
  }
}

// MARK: - View Body and Basic Modifiers

extension TiledView {

  public var body: some View {
    GeometryReader { proxy in
      TiledViewRepresentable(
        dataSource: dataSource,
        scrollPosition: $scrollPosition,
        cellStates: cellStates,
        onTiledScrollGeometryChange: onTiledScrollGeometryChange,
        onTapBackground: onTapBackground,
        onDragIntoBottomSafeArea: onDragIntoBottomSafeArea,
        additionalContentInset: additionalContentInset,
        swiftUIWorldSafeAreaInset: proxy.safeAreaInsets,
        revealConfiguration: revealConfiguration,
        prependLoader: prependLoader,
        appendLoader: appendLoader,
        typingIndicator: typingIndicator,
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

  /// Sets the configuration for the swipe-to-reveal gesture.
  ///
  /// Use this to customize the reveal behavior or disable it entirely.
  /// The reveal gesture allows users to swipe left to reveal timestamps
  /// or other content on the right side of messages.
  ///
  /// ```swift
  /// TiledView(...)
  ///   .revealConfiguration(.init(maxOffset: 100))
  /// ```
  public consuming func revealConfiguration(
    _ configuration: RevealConfiguration
  ) -> Self {
    self.revealConfiguration = configuration
    return self
  }
}

