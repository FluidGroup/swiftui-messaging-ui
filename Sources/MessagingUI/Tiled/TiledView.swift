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

  func interpolated(
    to target: UIEdgeInsets,
    progress: CGFloat
  ) -> UIEdgeInsets {
    let progress = min(max(progress, 0), 1)
    return UIEdgeInsets(
      top: top + (target.top - top) * progress,
      left: left + (target.left - left) * progress,
      bottom: bottom + (target.bottom - bottom) * progress,
      right: right + (target.right - right) * progress
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

  /// Whether the indicator is currently included in the visible content bounds.
  var isIndicatorVisible: Bool = false

  /// Generation token used to cancel deferred indicator presentation.
  var indicatorVisibilityGeneration: UInt = 0

  /// Pending work used to move indicator dismissal after item insertion settles.
  var indicatorHideWorkItem: DispatchWorkItem?
  var pendingIndicatorHideGeneration: UInt?

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

  /// Whether the loader indicator should be visible and participate in scrollable content bounds.
  var shouldShowIndicator: Bool {
    loader != nil && isIndicatorVisible
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
/// TiledView(items: messages, scrollPosition: $scrollPosition) { message in
///   MessageBubbleCell(item: message)
/// }
/// .prependLoader(.loader(perform: {
///   await store.loadOlder()
/// }) {
///   ProgressView()
/// })
///
/// // Sync mode (manual loading state)
/// TiledView(...)
/// .prependLoader(.loader(
///   perform: { store.loadOlder() },
///   isProcessing: store.isPrependLoading
/// ) {
///   ProgressView()
/// })
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
  /// Use this when you want to explicitly pass a disabled loader to a modifier.
  /// Note: Since auxiliary content uses modifiers, you can simply omit the modifier instead.
  /// ```swift
  /// TiledView(...)
  ///   .prependLoader(.loader(perform: { ... }) { ... })
  ///   // appendLoader is disabled by default (modifier not called)
  /// ```
  public static var disabled: Loader<Never>? { nil }
}

// MARK: - TypingIndicator

/// The current display phase of a typing indicator.
public enum TypingIndicatorPhase: Equatable, Sendable {
  case appearing
  case visible
  case dismissing
}

/// Configuration for displaying a typing indicator at the bottom of the message list.
///
/// Use this to show when other users are typing in a chat conversation.
/// The indicator appears below the last message and above the append loader.
///
/// ```swift
/// TiledView(items: messages, scrollPosition: $scrollPosition) { message in
///   MessageBubbleCell(item: message)
/// }
/// .typingIndicator(.indicator(isVisible: store.isTyping) {
///   TypingBubbleView(users: store.typingUsers)
/// })
/// ```
public struct TypingIndicator<Content: View> {

  /// Whether the typing indicator should be visible
  let isVisible: Bool

  /// The view to display as the typing indicator
  let content: (TypingIndicatorPhase) -> Content

  /// Creates a typing indicator configuration.
  ///
  /// - Parameters:
  ///   - isVisible: Whether to show the indicator
  ///   - content: The indicator view for the current display phase.
  public static func indicator(
    isVisible: Bool,
    @ViewBuilder content: @escaping (TypingIndicatorPhase) -> Content
  ) -> Self {
    TypingIndicator(isVisible: isVisible, content: content)
  }

  /// Creates a typing indicator configuration.
  ///
  /// - Parameters:
  ///   - isVisible: Whether to show the indicator
  ///   - content: The indicator view (e.g., animated dots bubble)
  public static func indicator(
    isVisible: Bool,
    @ViewBuilder content: @escaping () -> Content
  ) -> Self {
    TypingIndicator(isVisible: isVisible) { _ in
      content()
    }
  }
}

extension Optional where Wrapped == TypingIndicator<Never> {
  /// A disabled typing indicator that never shows.
  ///
  /// Note: Since auxiliary content uses modifiers, you can simply omit the
  /// `.typingIndicator()` modifier instead.
  public static var disabled: TypingIndicator<Never>? { nil }
}

// MARK: - HeaderContent

/// Configuration for displaying a static header at the top of the message list.
///
/// Use this to show content like "Start of conversation" or channel info
/// between the prepend loader and the first message item.
///
/// ```swift
/// TiledView(items: messages, scrollPosition: $scrollPosition) { message in
///   MessageBubbleCell(item: message)
/// }
/// .headerContent(.header {
///   Text("Start of conversation")
///     .foregroundStyle(.secondary)
///     .padding()
/// })
/// ```
public struct HeaderContent<Content: View> {

  let content: Content

  /// Creates a header content configuration.
  ///
  /// - Parameter content: The view to display as the header
  public static func header(
    @ViewBuilder content: () -> Content
  ) -> Self {
    HeaderContent(content: content())
  }
}

extension Optional where Wrapped == HeaderContent<Never> {
  /// A disabled header content that never shows.
  ///
  /// Note: Since auxiliary content uses modifiers, you can simply omit the
  /// `.headerContent()` modifier instead.
  public static var disabled: HeaderContent<Never>? { nil }
}

// MARK: - TiledUIView

final class TiledUIView<
  Item: Identifiable & Equatable,
  Cell: View,
  PrependLoadingView: View,
  AppendLoadingView: View,
  TypingIndicatorView: View,
  HeaderContentView: View,
  StateValue
>: UIView, UICollectionViewDataSource, UICollectionViewDelegate, UIGestureRecognizerDelegate {

  private let tiledLayout: TiledCollectionViewLayout = .init()
  private var collectionView: UICollectionView!

  private var items: Deque<Item> = []
  private var displayedAccessoryState = DisplayedAccessoryState()
  private let cellBuilder: (Item, CellReveal?, CellStateStorage<StateValue>) -> Cell
  private let makeInitialState: (Item) -> StateValue

  private enum AccessoryDisplayItem: Equatable {
    case prependLoader
    case headerContent
    case typingIndicator
    case appendLoader
  }

  private enum DisplayItemKind: String {
    case item
    case prependLoader
    case headerContent
    case typingIndicator
    case appendLoader
    case empty
  }

  private typealias DisplaySection = TiledCollectionViewLayout.DisplaySection
  private typealias PositionPreservation = TiledCollectionViewLayout.PositionPreservation

  private struct DisplayedAccessoryState {
    var hasPrependLoader = false
    var hasHeaderContent = false
    var hasTypingIndicator = false
    var hasAppendLoader = false

    func contains(_ displayItem: AccessoryDisplayItem) -> Bool {
      switch displayItem {
      case .prependLoader:
        hasPrependLoader
      case .headerContent:
        hasHeaderContent
      case .typingIndicator:
        hasTypingIndicator
      case .appendLoader:
        hasAppendLoader
      }
    }

    mutating func set(_ displayItem: AccessoryDisplayItem, visible: Bool) {
      switch displayItem {
      case .prependLoader:
        hasPrependLoader = visible
      case .headerContent:
        hasHeaderContent = visible
      case .typingIndicator:
        hasTypingIndicator = visible
      case .appendLoader:
        hasAppendLoader = visible
      }
    }
  }

  /// prototype cell for size measurement
  private let itemSizingCell = TiledViewCell<Cell>()
  private let prependLoaderSizingCell = TiledViewCell<PrependLoadingView>()
  private let headerContentSizingCell = TiledViewCell<HeaderContentView>()
  private let typingIndicatorSizingCell = TiledViewCell<TypingIndicatorView>()
  private let appendLoaderSizingCell = TiledViewCell<AppendLoadingView>()

  /// Item snapshot diff tracking
  private var isApplyingItemChanges: Bool = false
  private var queuedItems: [Item]?
  private var hasAppliedItemSnapshot: Bool = false

  /// Edge load triggers
  private var prependTrigger = EdgeLoadTrigger<PrependLoadingView>()
  private var appendTrigger = EdgeLoadTrigger<AppendLoadingView>()
  private let loadingIndicatorHideDelay: TimeInterval = 0.12
  private let loadingIndicatorRemovalAnimationDuration: TimeInterval = 0.55

  /// Scroll position tracking
  private var lastAppliedScrollVersion: UInt = 0

  /// Spring animator for programmatic scroll animations.
  private var springAnimator: SpringScrollAnimator?

  /// Spring animator for edge content inset changes caused by hiding loaders.
  private var hiddenEdgeContentInsetAnimator: SpringAnimator?
  private var hiddenEdgeContentInsetAnimationGeneration: UInt = 0

  /// Whether the current scroll movement was initiated by the user's pan gesture.
  private var isUserScrollSessionActive: Bool = false

  /// True while the typing indicator is being scrolled out before removal.
  private var isAnimatingTypingIndicatorRemoval: Bool = false
  private var isTypingIndicatorIncludedInContentBounds: Bool = false
  private var typingIndicatorRemovalWorkItem: DispatchWorkItem?
  private var typingIndicatorRemovalGeneration: UInt = 0
  private let typingIndicatorRemovalDelay: TimeInterval = 0.25
  private let typingIndicatorRemovalAnimationDuration: TimeInterval = 0.55

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

  /// Dedicated pan gesture for detecting drags into the bottom safe area.
  private var bottomSafeAreaPanGesture: UIPanGestureRecognizer?

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
    prependTrigger.loader = prepend
    appendTrigger.loader = append
    if prepend == nil {
      resetPrependLoadingIndicatorVisibility()
    } else {
      synchronizePrependLoadingIndicatorVisibility()
    }
    if append == nil {
      resetAppendLoadingIndicatorVisibility()
    } else {
      synchronizeAppendLoadingIndicatorVisibility()
    }

    guard hasAppliedItemSnapshot else { return }
    updateLoadingIndicatorVisibility()
  }

  // MARK: - Typing Indicator

  /// Current typing indicator configuration
  private var typingIndicator: TypingIndicator<TypingIndicatorView>?
  private var typingIndicatorPhase: TypingIndicatorPhase = .visible

  /// Sets the typing indicator and updates visibility.
  func setTypingIndicator(_ indicator: TypingIndicator<TypingIndicatorView>?) {
    typingIndicator = indicator

    guard hasAppliedItemSnapshot else { return }
    updateTypingIndicatorVisibility()
  }

  // MARK: - Header Content

  /// Current header content configuration
  private var headerContent: HeaderContent<HeaderContentView>?

  /// Sets the header content and updates visibility.
  func setHeaderContent(_ header: HeaderContent<HeaderContentView>?) {
    headerContent = header

    guard hasAppliedItemSnapshot else { return }
    updateHeaderContentVisibility()
  }

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
  private var storageMap: [Item.ID: CellStateStorage<StateValue>] = [:]
  
  private var pendingActionsOnLayoutSubviews: [() -> Void] = []

  init(
    makeInitialState: @escaping (Item) -> StateValue,
    cellBuilder: @escaping (Item, CellReveal?, CellStateStorage<StateValue>) -> Cell
  ) {
    self.makeInitialState = makeInitialState
    self.cellBuilder = cellBuilder
    super.init(frame: .zero)

    do {
      tiledLayout.itemSizeProviderForIndexPath = { [weak self] indexPath, width in
        self?.measureSize(at: indexPath, width: width)
      }
      tiledLayout.sectionItemCountsProvider = { [weak self] in
        self?.displaySectionItemCounts() ?? []
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
      
      registerCell(TiledViewCell<Cell>.self, kind: .item)
      registerCell(TiledViewCell<PrependLoadingView>.self, kind: .prependLoader)
      registerCell(TiledViewCell<HeaderContentView>.self, kind: .headerContent)
      registerCell(TiledViewCell<TypingIndicatorView>.self, kind: .typingIndicator)
      registerCell(TiledViewCell<AppendLoadingView>.self, kind: .appendLoader)
      registerCell(TiledViewCell<EmptyView>.self, kind: .empty)

      do {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTapBackground(_:)))
        tapGesture.cancelsTouchesInView = false
        collectionView.addGestureRecognizer(tapGesture)
      }

      /// setup 
      do {
        let bottomSafeAreaPanGesture = UIPanGestureRecognizer(
          target: self,
          action: #selector(handleBottomSafeAreaPanGesture(_:))
        )
        
        bottomSafeAreaPanGesture.cancelsTouchesInView = false
        bottomSafeAreaPanGesture.delegate = self
        collectionView.addGestureRecognizer(bottomSafeAreaPanGesture)
        self.bottomSafeAreaPanGesture = bottomSafeAreaPanGesture
      }

      // Setup reveal pan gesture for horizontal swipe-to-reveal
      do {
        let revealGesture = UIPanGestureRecognizer(target: self, action: #selector(handleRevealPanGesture(_:)))
        revealGesture.delegate = self
        collectionView.addGestureRecognizer(revealGesture)
        revealGestureState.panGesture = revealGesture
      }

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

  private func registerCell<Content: View>(
    _ cellType: TiledViewCell<Content>.Type,
    kind: DisplayItemKind
  ) {
    collectionView.register(
      cellType,
      forCellWithReuseIdentifier: TiledViewCell<Content>.reuseIdentifier(for: kind.rawValue)
    )
  }
  
  override func safeAreaInsetsDidChange() {
    super.safeAreaInsetsDidChange()
    applyContentInsets()
  }

  @objc private func handleTapBackground(_ gesture: UITapGestureRecognizer) {
    onTapBackground?()
  }

  // MARK: - Cell State Storage

  /// Gets or creates a CellStateStorage for the given item
  private func getOrCreateStorage(for item: Item) -> CellStateStorage<StateValue> {
    if let existing = storageMap[item.id] {
      return existing
    }
    let storage = CellStateStorage(makeInitialState(item))
    storageMap[item.id] = storage
    return storage
  }

  private func measureSize(at indexPath: IndexPath, width: CGFloat) -> CGSize? {
    guard let section = DisplaySection(rawValue: indexPath.section) else { return nil }

    switch section {
    case .messages:
      guard indexPath.item >= 0, indexPath.item < items.count else { return .zero }
      let item = items[indexPath.item]
      let storage = getOrCreateStorage(for: item)
      return measureHostedCellSize(cellBuilder(item, cellReveal, storage), width: width, using: itemSizingCell)

    case .prependLoader, .headerContent, .typingIndicator, .appendLoader:
      guard let displayItem = accessoryDisplayItem(at: indexPath) else { return nil }
      return measureSize(for: displayItem, width: width)
    }
  }

  private func measureSize(for displayItem: AccessoryDisplayItem, width: CGFloat) -> CGSize? {
    switch displayItem {
    case .prependLoader:
      guard let loader = prependTrigger.loader else { return .zero }
      return measureHostedCellSize(loader.indicator, width: width, using: prependLoaderSizingCell)

    case .headerContent:
      guard let headerContent else { return .zero }
      return measureHostedCellSize(headerContent.content, width: width, using: headerContentSizingCell)

    case .typingIndicator:
      guard let typingIndicator else { return .zero }
      return measureHostedCellSize(
        typingIndicator.content(typingIndicatorPhase),
        width: width,
        using: typingIndicatorSizingCell
      )

    case .appendLoader:
      guard let loader = appendTrigger.loader else { return .zero }
      return measureHostedCellSize(loader.indicator, width: width, using: appendLoaderSizingCell)
    }
  }

  private func measureHostedCellSize<Content: View>(
    _ content: Content,
    width: CGFloat,
    using sizingCell: TiledViewCell<Content>
  ) -> CGSize {
    sizingCell.configure(with: content)
    sizingCell.bounds.size.width = width
    sizingCell.contentView.bounds.size.width = width
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

  private func displaySectionItemCounts() -> [Int] {
    DisplaySection.allCases.map { displayItemCount(in: $0) }
  }

  private var totalDisplayItemCount: Int {
    displaySectionItemCounts().reduce(0, +)
  }

  private func displayItemCount(in section: DisplaySection) -> Int {
    switch section {
    case .prependLoader:
      displayedAccessoryState.hasPrependLoader ? 1 : 0
    case .headerContent:
      displayedAccessoryState.hasHeaderContent ? 1 : 0
    case .messages:
      items.count
    case .typingIndicator:
      displayedAccessoryState.hasTypingIndicator ? 1 : 0
    case .appendLoader:
      displayedAccessoryState.hasAppendLoader ? 1 : 0
    }
  }

  private func currentAccessoryState() -> DisplayedAccessoryState {
    DisplayedAccessoryState(
      hasPrependLoader: prependTrigger.loader != nil,
      hasHeaderContent: headerContent != nil,
      hasTypingIndicator: typingIndicator != nil,
      hasAppendLoader: appendTrigger.loader != nil
    )
  }

  private func accessoryDisplayItem(at indexPath: IndexPath) -> AccessoryDisplayItem? {
    guard let section = DisplaySection(rawValue: indexPath.section) else { return nil }

    switch section {
    case .prependLoader:
      guard indexPath.item == 0, displayedAccessoryState.hasPrependLoader else { return nil }
      return .prependLoader
    case .headerContent:
      guard indexPath.item == 0, displayedAccessoryState.hasHeaderContent else { return nil }
      return .headerContent
    case .messages:
      return nil
    case .typingIndicator:
      guard indexPath.item == 0, displayedAccessoryState.hasTypingIndicator else { return nil }
      return .typingIndicator
    case .appendLoader:
      guard indexPath.item == 0, displayedAccessoryState.hasAppendLoader else { return nil }
      return .appendLoader
    }
  }

  private func indexPath(for displayItem: AccessoryDisplayItem) -> IndexPath? {
    switch displayItem {
    case .prependLoader:
      guard displayedAccessoryState.hasPrependLoader else { return nil }
      return DisplaySection.prependLoader.indexPath()
    case .headerContent:
      guard displayedAccessoryState.hasHeaderContent else { return nil }
      return DisplaySection.headerContent.indexPath()
    case .typingIndicator:
      guard displayedAccessoryState.hasTypingIndicator else { return nil }
      return DisplaySection.typingIndicator.indexPath()
    case .appendLoader:
      guard displayedAccessoryState.hasAppendLoader else { return nil }
      return DisplaySection.appendLoader.indexPath()
    }
  }

  private func accessorySection(for displayItem: AccessoryDisplayItem) -> DisplaySection? {
    switch displayItem {
    case .prependLoader:
      .prependLoader
    case .headerContent:
      .headerContent
    case .typingIndicator:
      .typingIndicator
    case .appendLoader:
      .appendLoader
    }
  }

  private func reconfigureAccessoryDisplayItem(_ displayItem: AccessoryDisplayItem) {
    guard let indexPath = indexPath(for: displayItem) else { return }
    collectionView.reconfigureItems(at: [indexPath])
  }

  private func primeCollectionViewItemCountForBatchUpdate() {
    // We intentionally mutate the data source and layout before performBatchUpdates
    // so UICollectionView can resolve stable before/after layout attributes. Make
    // sure UIKit has observed the pre-mutation item count before we do that.
    guard collectionView.numberOfSections > 0 else { return }
    for section in 0..<collectionView.numberOfSections {
      _ = collectionView.numberOfItems(inSection: section)
    }
  }

  private func setAccessoryDisplayItem(
    _ displayItem: AccessoryDisplayItem,
    visible: Bool,
    positionPreservation: PositionPreservation,
    beforeUpdate: (() -> Void)? = nil,
    completion: (() -> Void)? = nil
  ) {
    let isCurrentlyDisplayed = displayedAccessoryState.contains(displayItem)

    let finishUpdate = {
      completion?()
    }

    switch (isCurrentlyDisplayed, visible) {
    case (true, false):
      guard let indexPath = indexPath(for: displayItem) else {
        finishUpdate()
        return
      }
      beforeUpdate?()
      primeCollectionViewItemCountForBatchUpdate()
      tiledLayout.beginBatchUpdates()
      displayedAccessoryState.set(displayItem, visible: false)
      tiledLayout.enqueuePendingUpdate(.removeItems(at: [indexPath], preserving: positionPreservation))

      UIView.performWithoutAnimation {
        collectionView.performBatchUpdates({
          collectionView.deleteItems(at: [indexPath])
        }, completion: { _ in
          self.tiledLayout.endBatchUpdates()
          finishUpdate()
        })
      }

    case (false, true):
      guard let section = accessorySection(for: displayItem) else {
        finishUpdate()
        return
      }
      let indexPath = section.indexPath()
      beforeUpdate?()
      primeCollectionViewItemCountForBatchUpdate()
      tiledLayout.beginBatchUpdates()
      displayedAccessoryState.set(displayItem, visible: true)
      tiledLayout.enqueuePendingUpdate(
        .insertItems(count: 1, at: indexPath, preserving: positionPreservation)
      )

      UIView.performWithoutAnimation {
        collectionView.performBatchUpdates({
          collectionView.insertItems(at: [indexPath])
        }, completion: { _ in
          self.tiledLayout.endBatchUpdates()
          finishUpdate()
        })
      }

    case (true, true):
      reconfigureAccessoryDisplayItem(displayItem)
      finishUpdate()

    case (false, false):
      finishUpdate()
    }
  }

  private func remeasureAccessoryDisplayItem(
    _ displayItem: AccessoryDisplayItem,
    positionPreservation: PositionPreservation
  ) {
    guard let indexPath = indexPath(for: displayItem) else { return }

    let height = measuredAccessoryHeight(for: displayItem)
    switch positionPreservation {
    case .itemsBeforeMutation:
      tiledLayout.updateItemHeight(at: indexPath, newHeight: height)
    case .itemsAfterMutation:
      tiledLayout.updateItemHeightKeepingTrailingPositions(at: indexPath, newHeight: height)
    }
    tiledLayout.invalidateLayout()
  }

  private func measuredAccessoryHeight(for displayItem: AccessoryDisplayItem) -> CGFloat {
    measureSize(for: displayItem, width: collectionView.bounds.width)?.height ?? 0
  }

  private func updateHiddenEdgeContentInset(animated: Bool = false) {
    guard collectionView != nil else { return }

    setHiddenEdgeContentInset(
      hiddenEdgeContentInset(),
      animated: animated
    )
  }

  private func setHiddenEdgeContentInset(
    _ inset: UIEdgeInsets,
    animated: Bool
  ) {
    guard tiledLayout.hiddenEdgeContentInset != inset else { return }

    hiddenEdgeContentInsetAnimationGeneration &+= 1
    let generation = hiddenEdgeContentInsetAnimationGeneration
    hiddenEdgeContentInsetAnimator?.stop(finished: false)
    hiddenEdgeContentInsetAnimator = nil

    guard animated else {
      tiledLayout.hiddenEdgeContentInset = inset
      return
    }

    collectionView.layoutIfNeeded()
    let startInset = tiledLayout.hiddenEdgeContentInset
    let animator = SpringAnimator(
      spring: Spring(duration: loadingIndicatorRemovalAnimationDuration, bounce: 0)
    )
    hiddenEdgeContentInsetAnimator = animator

    // Animate the inset value frame-by-frame so UIScrollView receives each
    // contentInset change and can apply its built-in contentOffset adjustment.
    animator.animate(
      from: 0,
      to: 1,
      onUpdate: { [weak self] progress in
        guard let self else { return }
        guard self.hiddenEdgeContentInsetAnimationGeneration == generation else { return }

        self.tiledLayout.hiddenEdgeContentInset = startInset.interpolated(
          to: inset,
          progress: CGFloat(progress)
        )
        self.collectionView.layoutIfNeeded()
      },
      completion: { [weak self] _ in
        guard let self else { return }
        guard self.hiddenEdgeContentInsetAnimationGeneration == generation else { return }

        self.hiddenEdgeContentInsetAnimator = nil
        self.tiledLayout.hiddenEdgeContentInset = inset
        self.collectionView.layoutIfNeeded()
        self.clampContentOffsetToScrollableBounds(animated: false)
      }
    )
  }

  private func hiddenEdgeContentInset() -> UIEdgeInsets {
    let top: CGFloat
    if displayedAccessoryState.hasPrependLoader,
       !prependTrigger.shouldShowIndicator {
      top = measuredAccessoryHeight(for: .prependLoader)
    } else {
      top = 0
    }

    var bottom: CGFloat = 0
    let appendLoaderIsVisible = appendTrigger.loader != nil && appendTrigger.shouldShowIndicator
    if appendTrigger.loader != nil, !appendTrigger.shouldShowIndicator {
      bottom += measuredAccessoryHeight(for: .appendLoader)
    }

    if !appendLoaderIsVisible,
       displayedAccessoryState.hasTypingIndicator,
       !isTypingIndicatorIncludedInContentBounds {
      bottom += measuredAccessoryHeight(for: .typingIndicator)
    }

    return UIEdgeInsets(
      top: top,
      left: 0,
      bottom: bottom,
      right: 0
    )
  }

  // MARK: - Items-based API

  /// Applies a new item snapshot by diffing it against the currently displayed items.
  func applyItems(_ newItems: [Item]) {
    assert(
      Set(newItems.map(\.id)).count == newItems.count,
      "TiledView requires each item to have a unique id."
    )

    if isApplyingItemChanges {
      queuedItems = newItems
      return
    }

    if !hasAppliedItemSnapshot {
      hasAppliedItemSnapshot = true
      isApplyingItemChanges = true
      applyChange(.replace(newItems)) { [weak self] in
        guard let self else { return }
        self.isApplyingItemChanges = false
        self.finishPendingLoadingIndicatorHides()
      }
      return
    }

    isApplyingItemChanges = true
    recursive_drainItemChanges(to: newItems)
  }

  private func recursive_drainItemChanges(to newItems: [Item]) {
    let changes = TiledItemChange.make(from: items, to: newItems)
    recursive_drainItemChanges(
      changes,
      cursor: 0
    )
  }

  private func recursive_drainItemChanges(
    _ changes: [TiledItemChange<Item>],
    cursor: Int
  ) {
    guard cursor < changes.count else {
      if let queuedItems {
        self.queuedItems = nil
        recursive_drainItemChanges(to: queuedItems)
      } else {
        isApplyingItemChanges = false
        finishPendingLoadingIndicatorHides()
      }
      return
    }

    applyChange(changes[cursor]) { [weak self] in
      guard let self else { return }

      if let queuedItems {
        self.queuedItems = nil
        recursive_drainItemChanges(to: queuedItems)
      } else {
        recursive_drainItemChanges(changes, cursor: cursor + 1)
      }
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    updateHiddenEdgeContentInset()
    
    // Execute any pending actions after layout
    let actions = pendingActionsOnLayoutSubviews
    pendingActionsOnLayoutSubviews.removeAll()
    DispatchQueue.main.async {
      for action in actions {
        action()
      }
    }

  }

  private func applyChange(
    _ change: TiledItemChange<Item>,
    completion: @escaping () -> Void
  ) {
    switch change {
    case .replace(let newItems):
      tiledLayout.clear()
      items = Deque(newItems)
      displayedAccessoryState = currentAccessoryState()
      tiledLayout.resetItemMetrics(expectedItemCount: totalDisplayItemCount)
      collectionView.reloadData()
      updateHiddenEdgeContentInset()

      pendingActionsOnLayoutSubviews.append { [weak self, scrollsToBottomOnReplace] in
        guard let self else { return }
        
        if scrollsToBottomOnReplace {
          scrollTo(edge: .bottom, animated: false)
        }
      }
      setNeedsLayout()
      completion()

    case .prepend(let newItems):
      guard !newItems.isEmpty else {
        completion()
        return
      }

      let insertionIndexPath = DisplaySection.messages.indexPath(item: 0)
      primeCollectionViewItemCountForBatchUpdate()
      tiledLayout.beginBatchUpdates()
      items.insert(contentsOf: newItems, at: 0)
      tiledLayout.enqueuePendingUpdate(
        .insertItems(count: newItems.count, at: insertionIndexPath, preserving: .itemsAfterMutation)
      )

      let indexPaths = (0..<newItems.count).map {
        DisplaySection.messages.indexPath(item: $0)
      }

      UIView.performWithoutAnimation {
        collectionView.performBatchUpdates({
          collectionView.insertItems(at: indexPaths)
        }, completion: { _ in
          self.tiledLayout.endBatchUpdates()
          completion()
        })
      }

    case .append(let newItems):
      let startingIndex = items.count
      guard !newItems.isEmpty else {
        completion()
        return
      }

      let insertionIndexPath = DisplaySection.messages.indexPath(item: startingIndex)
      primeCollectionViewItemCountForBatchUpdate()
      tiledLayout.beginBatchUpdates()
      items.append(contentsOf: newItems)
      tiledLayout.enqueuePendingUpdate(
        .insertItems(count: newItems.count, at: insertionIndexPath, preserving: .itemsBeforeMutation)
      )

      let indexPaths = (startingIndex..<startingIndex + newItems.count).map {
        DisplaySection.messages.indexPath(item: $0)
      }

      UIView.performWithoutAnimation {
        collectionView.performBatchUpdates({
          collectionView.insertItems(at: indexPaths)
        }, completion: { [weak self] _ in
          guard let self else { return }
          self.tiledLayout.endBatchUpdates()

          if autoScrollsToBottomOnAppend {
            scrollTo(edge: .bottom, animated: true)
          }

          completion()
        })
      }

    case .insert(let index, let newItems):
      guard !newItems.isEmpty else {
        completion()
        return
      }

      let insertionIndexPath = DisplaySection.messages.indexPath(item: index)
      primeCollectionViewItemCountForBatchUpdate()
      tiledLayout.beginBatchUpdates()
      for (offset, item) in newItems.enumerated() {
        items.insert(item, at: index + offset)
      }
      tiledLayout.enqueuePendingUpdate(
        .insertItems(count: newItems.count, at: insertionIndexPath, preserving: .itemsBeforeMutation)
      )

      let indexPaths = (index..<index + newItems.count).map {
        DisplaySection.messages.indexPath(item: $0)
      }

      UIView.performWithoutAnimation {
        collectionView.performBatchUpdates({
          collectionView.insertItems(at: indexPaths)
        }, completion: { _ in
          self.tiledLayout.endBatchUpdates()
          completion()
        })
      }

    case .update(let newItems):
      let indexPaths = newItems.compactMap { item -> IndexPath? in
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return nil }
        return DisplaySection.messages.indexPath(item: index)
      }

      guard !indexPaths.isEmpty else {
        completion()
        return
      }
      primeCollectionViewItemCountForBatchUpdate()
      for item in newItems {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
          items[index] = item
        }
      }

      UIView.performWithoutAnimation {
        collectionView.performBatchUpdates({
          collectionView.reconfigureItems(at: indexPaths)
        }, completion: { _ in
          completion()
        })
      }

    case .remove(let ids):
      let idsSet = Set(ids)
      // Find indices before removing items
      let indicesToRemove = items.enumerated()
        .filter { idsSet.contains($0.element.id) }
        .map { $0.offset }
      guard !indicesToRemove.isEmpty else {
        completion()
        return
      }

      let indexPaths = indicesToRemove.map {
        DisplaySection.messages.indexPath(item: $0)
      }
      primeCollectionViewItemCountForBatchUpdate()
      tiledLayout.beginBatchUpdates()
      items.removeAll { idsSet.contains($0.id) }
      tiledLayout.enqueuePendingUpdate(
        .removeItems(at: indexPaths, preserving: .itemsBeforeMutation)
      )

      UIView.performWithoutAnimation {
        collectionView.performBatchUpdates({
          collectionView.deleteItems(at: indexPaths)
        }, completion: { _ in
          self.tiledLayout.endBatchUpdates()
          completion()
        })
      }
    }
  }

  // MARK: UICollectionViewDataSource

  func numberOfSections(in collectionView: UICollectionView) -> Int {
    DisplaySection.count
  }

  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    guard let section = DisplaySection(rawValue: section) else { return 0 }
    return displayItemCount(in: section)
  }

  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    guard let section = DisplaySection(rawValue: indexPath.section) else {
      return dequeueEmptyCell(collectionView, at: indexPath)
    }

    switch section {
    case .messages:
      if indexPath.item < items.count {
        let item = items[indexPath.item]
        let storage = getOrCreateStorage(for: item)
        return dequeueCell(collectionView, at: indexPath, kind: .item, content: cellBuilder(item, cellReveal, storage))
      } else {
        return dequeueEmptyCell(collectionView, at: indexPath)
      }

    case .prependLoader, .headerContent, .typingIndicator, .appendLoader:
      guard let displayItem = accessoryDisplayItem(at: indexPath) else {
        return dequeueEmptyCell(collectionView, at: indexPath)
      }

      switch displayItem {
      case .prependLoader:
        if let loader = prependTrigger.loader {
          let cell = dequeueCell(collectionView, at: indexPath, kind: .prependLoader, content: loader.indicator)
          cell.contentView.alpha = prependTrigger.shouldShowIndicator ? 1 : 0
          return cell
        } else {
          return dequeueEmptyCell(collectionView, at: indexPath)
        }

      case .headerContent:
        if let headerContent {
          return dequeueCell(collectionView, at: indexPath, kind: .headerContent, content: headerContent.content)
        } else {
          return dequeueEmptyCell(collectionView, at: indexPath)
        }

      case .typingIndicator:
        if let typingIndicator {
          let cell = dequeueCell(
            collectionView,
            at: indexPath,
            kind: .typingIndicator,
            content: typingIndicator.content(typingIndicatorPhase)
          )
          cell.contentView.alpha = isTypingIndicatorIncludedInContentBounds || isAnimatingTypingIndicatorRemoval ? 1 : 0
          return cell
        } else {
          return dequeueEmptyCell(collectionView, at: indexPath)
        }

      case .appendLoader:
        if let loader = appendTrigger.loader {
          let cell = dequeueCell(collectionView, at: indexPath, kind: .appendLoader, content: loader.indicator)
          cell.contentView.alpha = appendTrigger.shouldShowIndicator ? 1 : 0
          return cell
        } else {
          return dequeueEmptyCell(collectionView, at: indexPath)
        }
      }
    }
  }

  private func dequeueCell<Content: View>(
    _ collectionView: UICollectionView,
    at indexPath: IndexPath,
    kind: DisplayItemKind,
    content: Content
  ) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(
      withReuseIdentifier: TiledViewCell<Content>.reuseIdentifier(for: kind.rawValue),
      for: indexPath
    ) as! TiledViewCell<Content>
    cell.configure(with: content)
    return cell
  }

  private func dequeueEmptyCell(
    _ collectionView: UICollectionView,
    at indexPath: IndexPath
  ) -> UICollectionViewCell {
    dequeueCell(collectionView, at: indexPath, kind: .empty, content: EmptyView())
  }

  // MARK: UICollectionViewDelegate

  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    // Override in subclass or use closure if needed
  }

  // MARK: - UIScrollViewDelegate

  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    defer {
      notifyScrollGeometry()
    }

    guard isUserScrollSessionActive else { return }

    updateEdgeLoadTriggers(scrollView)
  }

  private func updateEdgeLoadTriggers(_ scrollView: UIScrollView) {
    // Prepend trigger
    let offsetY = scrollView.contentOffset.y + scrollView.contentInset.top
    if offsetY <= prependTrigger.threshold {
      triggerPrependLoadIfNeeded()
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
  }

  private func triggerPrependLoadIfNeeded() {
    guard prependTrigger.loader != nil else { return }
    guard !prependTrigger.isTriggered && !prependTrigger.isLoading else { return }

    prependTrigger.isTriggered = true
    triggerPrependLoad()
  }

  private func triggerPrependLoadForScrollToTop() {
    guard prependTrigger.loader != nil else { return }
    guard !prependTrigger.isLoading else { return }

    // A status-bar tap is a fresh user intent even when the top-edge trigger is
    // still latched from a previous top pass.
    prependTrigger.isTriggered = true
    triggerPrependLoad()
  }

  private func triggerPrependLoad() {
    guard let loader = prependTrigger.loader else { return }

    switch loader.perform {
    case .async(let perform):
      prependTrigger.indicatorVisibilityGeneration &+= 1
      let generation = prependTrigger.indicatorVisibilityGeneration
      prependTrigger.indicatorHideWorkItem?.cancel()
      prependTrigger.indicatorHideWorkItem = nil
      prependTrigger.pendingIndicatorHideGeneration = nil
      // task != nil indicates loading state
      prependTrigger.task = Task { @MainActor [weak self] in
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          guard self.prependTrigger.indicatorVisibilityGeneration == generation else { return }
          guard self.prependTrigger.isLoading else { return }
          self.prependTrigger.indicatorHideWorkItem?.cancel()
          self.prependTrigger.indicatorHideWorkItem = nil
          self.prependTrigger.pendingIndicatorHideGeneration = nil
          self.prependTrigger.isIndicatorVisible = true
          self.updateLoadingIndicatorVisibility()
        }
        defer {
          if let self {
            self.prependTrigger.task = nil
            DispatchQueue.main.async { [weak self] in
              guard let self else { return }
              guard self.prependTrigger.indicatorVisibilityGeneration == generation else { return }
              self.requestPrependLoadingIndicatorHide(generation: generation)
            }
          }
        }
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
      appendTrigger.indicatorVisibilityGeneration &+= 1
      let generation = appendTrigger.indicatorVisibilityGeneration
      appendTrigger.indicatorHideWorkItem?.cancel()
      appendTrigger.indicatorHideWorkItem = nil
      appendTrigger.pendingIndicatorHideGeneration = nil
      // task != nil indicates loading state
      appendTrigger.task = Task { @MainActor [weak self] in
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          guard self.appendTrigger.indicatorVisibilityGeneration == generation else { return }
          guard self.appendTrigger.isLoading else { return }
          self.appendTrigger.indicatorHideWorkItem?.cancel()
          self.appendTrigger.indicatorHideWorkItem = nil
          self.appendTrigger.pendingIndicatorHideGeneration = nil
          self.appendTrigger.isIndicatorVisible = true
          self.updateLoadingIndicatorVisibility()
        }
        defer {
          if let self {
            self.appendTrigger.task = nil
            DispatchQueue.main.async { [weak self] in
              guard let self else { return }
              guard self.appendTrigger.indicatorVisibilityGeneration == generation else { return }
              self.requestAppendLoadingIndicatorHide(generation: generation)
            }
          }
        }
        await perform()
      }
    case .sync(let perform):
      // External loading state management via isProcessing
      perform()
    }
  }

  func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
    isUserScrollSessionActive = false
    triggerPrependLoadForScrollToTop()

    return true
  }

  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    isUserScrollSessionActive = true
  }

  func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
    hasDraggedIntoBottomSafeArea = false
    if !decelerate {
      isUserScrollSessionActive = false
    }
  }

  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
    hasDraggedIntoBottomSafeArea = false
    isUserScrollSessionActive = false
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

  @objc private func handleBottomSafeAreaPanGesture(_ gesture: UIPanGestureRecognizer) {
    switch gesture.state {
    case .began, .changed:
      checkDragIntoBottomSafeArea(gesture)
    case .ended, .cancelled, .failed:
      hasDraggedIntoBottomSafeArea = false
    default:
      break
    }
  }

  private func checkDragIntoBottomSafeArea(_ gesture: UIPanGestureRecognizer) {
    guard let onDragIntoBottomSafeArea else { return }

    let bottomSafeAreaHeight = tiledLayout.additionalContentInset.bottom
    guard bottomSafeAreaHeight > 0 else {
      hasDraggedIntoBottomSafeArea = false
      return
    }

    let touchLocation = gesture.location(in: self)
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
    if gestureRecognizer == bottomSafeAreaPanGesture || otherGestureRecognizer == bottomSafeAreaPanGesture {
      return true
    }
    // Allow reveal gesture to work with scroll view
    if gestureRecognizer == revealGestureState.panGesture || otherGestureRecognizer == revealGestureState.panGesture {
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
    isUserScrollSessionActive = false

    collectionView.layoutIfNeeded()

    // Cancel any existing animation
    springAnimator?.stop(finished: false)
    springAnimator = nil

    // Stop any existing deceleration
    collectionView.setContentOffset(collectionView.contentOffset, animated: false)

    if animated {
      let animator = SpringScrollAnimator()
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

  @discardableResult
  private func clampContentOffsetToScrollableBounds(animated: Bool) -> Bool {
    let scrollableBounds = scrollableContentOffsetBounds()

    let clampedOffsetY = min(
      max(collectionView.contentOffset.y, scrollableBounds.min),
      scrollableBounds.max
    )
    guard clampedOffsetY != collectionView.contentOffset.y else { return false }

    scrollToContentOffsetY(clampedOffsetY, animated: animated)
    return true
  }

  private func scrollableContentOffsetBounds() -> (min: CGFloat, max: CGFloat) {
    let inset = collectionView.adjustedContentInset
    let minOffsetY = -inset.top
    let maxOffsetY = max(
      minOffsetY,
      collectionView.contentSize.height - collectionView.bounds.height + inset.bottom
    )
    return (minOffsetY, maxOffsetY)
  }

  private func scrollToContentOffsetY(
    _ offsetY: CGFloat,
    animated: Bool,
    spring: Spring = .snappy,
    completion: (() -> Void)? = nil
  ) {
    isUserScrollSessionActive = false
    springAnimator?.stop(finished: false)
    springAnimator = nil
    collectionView.setContentOffset(collectionView.contentOffset, animated: false)

    if animated {
      let animator = SpringScrollAnimator(spring: spring)
      springAnimator = animator
      animator.animate(scrollView: collectionView, to: offsetY) { _ in
        completion?()
      }
    } else {
      collectionView.contentOffset = CGPoint(
        x: collectionView.contentOffset.x,
        y: offsetY
      )
      completion?()
    }
  }

  // MARK: - Loading Indicator Management

  private func resetPrependLoadingIndicatorVisibility() {
    prependTrigger.indicatorVisibilityGeneration &+= 1
    prependTrigger.indicatorHideWorkItem?.cancel()
    prependTrigger.indicatorHideWorkItem = nil
    prependTrigger.pendingIndicatorHideGeneration = nil
    prependTrigger.isIndicatorVisible = false
  }

  private func resetAppendLoadingIndicatorVisibility() {
    appendTrigger.indicatorVisibilityGeneration &+= 1
    appendTrigger.indicatorHideWorkItem?.cancel()
    appendTrigger.indicatorHideWorkItem = nil
    appendTrigger.pendingIndicatorHideGeneration = nil
    appendTrigger.isIndicatorVisible = false
  }

  private func synchronizePrependLoadingIndicatorVisibility() {
    guard prependTrigger.loader?.isProcessing != nil else { return }

    if prependTrigger.isLoading {
      prependTrigger.indicatorHideWorkItem?.cancel()
      prependTrigger.indicatorHideWorkItem = nil
      prependTrigger.pendingIndicatorHideGeneration = nil
      prependTrigger.isIndicatorVisible = true
    } else if prependTrigger.isIndicatorVisible {
      requestPrependLoadingIndicatorHide(generation: prependTrigger.indicatorVisibilityGeneration)
    }
  }

  private func synchronizeAppendLoadingIndicatorVisibility() {
    guard appendTrigger.loader?.isProcessing != nil else { return }

    if appendTrigger.isLoading {
      appendTrigger.indicatorHideWorkItem?.cancel()
      appendTrigger.indicatorHideWorkItem = nil
      appendTrigger.pendingIndicatorHideGeneration = nil
      appendTrigger.isIndicatorVisible = true
    } else if appendTrigger.isIndicatorVisible {
      requestAppendLoadingIndicatorHide(generation: appendTrigger.indicatorVisibilityGeneration)
    }
  }

  private func requestPrependLoadingIndicatorHide(generation: UInt) {
    guard prependTrigger.indicatorVisibilityGeneration == generation else { return }
    guard prependTrigger.loader != nil else { return }
    guard prependTrigger.pendingIndicatorHideGeneration != generation else { return }

    prependTrigger.indicatorHideWorkItem?.cancel()
    prependTrigger.pendingIndicatorHideGeneration = generation

    let workItem = DispatchWorkItem { [weak self] in
      self?.finishPrependLoadingIndicatorHide(generation: generation)
    }
    prependTrigger.indicatorHideWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + loadingIndicatorHideDelay, execute: workItem)
  }

  private func requestAppendLoadingIndicatorHide(generation: UInt) {
    guard appendTrigger.indicatorVisibilityGeneration == generation else { return }
    guard appendTrigger.loader != nil else { return }
    guard appendTrigger.pendingIndicatorHideGeneration != generation else { return }

    appendTrigger.indicatorHideWorkItem?.cancel()
    appendTrigger.pendingIndicatorHideGeneration = generation

    let workItem = DispatchWorkItem { [weak self] in
      self?.finishAppendLoadingIndicatorHide(generation: generation)
    }
    appendTrigger.indicatorHideWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + loadingIndicatorHideDelay, execute: workItem)
  }

  private func finishPendingLoadingIndicatorHides() {
    if let generation = prependTrigger.pendingIndicatorHideGeneration {
      finishPrependLoadingIndicatorHide(generation: generation)
    }
    if let generation = appendTrigger.pendingIndicatorHideGeneration {
      finishAppendLoadingIndicatorHide(generation: generation)
    }
  }

  private func finishPrependLoadingIndicatorHide(generation: UInt) {
    guard !isApplyingItemChanges else { return }
    guard prependTrigger.pendingIndicatorHideGeneration == generation else { return }
    guard prependTrigger.indicatorVisibilityGeneration == generation else { return }

    completePrependLoadingIndicatorHide(
      generation: generation,
      animatesHiddenEdgeContentInset: shouldAnimatePrependLoadingIndicatorRemoval()
    )
  }

  private func finishAppendLoadingIndicatorHide(generation: UInt) {
    guard !isApplyingItemChanges else { return }
    guard appendTrigger.pendingIndicatorHideGeneration == generation else { return }
    guard appendTrigger.indicatorVisibilityGeneration == generation else { return }

    completeAppendLoadingIndicatorHide(
      generation: generation,
      animatesHiddenEdgeContentInset: shouldAnimateAppendLoadingIndicatorRemoval()
    )
  }

  private func completePrependLoadingIndicatorHide(
    generation: UInt,
    animatesHiddenEdgeContentInset: Bool
  ) {
    guard prependTrigger.pendingIndicatorHideGeneration == generation else { return }
    guard prependTrigger.indicatorVisibilityGeneration == generation else { return }

    prependTrigger.indicatorHideWorkItem?.cancel()
    prependTrigger.indicatorHideWorkItem = nil
    prependTrigger.pendingIndicatorHideGeneration = nil
    prependTrigger.indicatorVisibilityGeneration &+= 1
    prependTrigger.isIndicatorVisible = false
    updateLoadingIndicatorVisibility(
      animatesHiddenEdgeContentInset: animatesHiddenEdgeContentInset
    )
    if !animatesHiddenEdgeContentInset {
      collectionView.layoutIfNeeded()
      clampContentOffsetToScrollableBounds(animated: false)
    }
  }

  private func completeAppendLoadingIndicatorHide(
    generation: UInt,
    animatesHiddenEdgeContentInset: Bool
  ) {
    guard appendTrigger.pendingIndicatorHideGeneration == generation else { return }
    guard appendTrigger.indicatorVisibilityGeneration == generation else { return }

    appendTrigger.indicatorHideWorkItem?.cancel()
    appendTrigger.indicatorHideWorkItem = nil
    appendTrigger.pendingIndicatorHideGeneration = nil
    appendTrigger.indicatorVisibilityGeneration &+= 1
    appendTrigger.isIndicatorVisible = false
    updateLoadingIndicatorVisibility(
      animatesHiddenEdgeContentInset: animatesHiddenEdgeContentInset
    )
    if !animatesHiddenEdgeContentInset {
      collectionView.layoutIfNeeded()
      clampContentOffsetToScrollableBounds(animated: false)
    }
  }

  private func shouldAnimatePrependLoadingIndicatorRemoval() -> Bool {
    guard let attributes = layoutAttributesForAccessoryDisplayItem(.prependLoader),
          attributes.frame.height > 0 else {
      return false
    }

    let scrollableBounds = scrollableContentOffsetBounds()
    let targetOffsetY = min(
      scrollableBounds.max,
      scrollableBounds.min + attributes.frame.height
    )
    return collectionView.contentOffset.y < targetOffsetY - 0.5
  }

  private func shouldAnimateAppendLoadingIndicatorRemoval() -> Bool {
    guard let attributes = layoutAttributesForAccessoryDisplayItem(.appendLoader),
          attributes.frame.height > 0 else {
      return false
    }

    let scrollableBounds = scrollableContentOffsetBounds()
    let targetOffsetY = max(
      scrollableBounds.min,
      scrollableBounds.max - attributes.frame.height
    )
    return collectionView.contentOffset.y > targetOffsetY + 0.5
  }

  private func layoutAttributesForAccessoryDisplayItem(
    _ displayItem: AccessoryDisplayItem
  ) -> UICollectionViewLayoutAttributes? {
    collectionView.layoutIfNeeded()

    guard let indexPath = indexPath(for: displayItem),
          let attributes = tiledLayout.layoutAttributesForItem(at: indexPath) else {
      return nil
    }

    return attributes
  }

  private func updateLoadingIndicatorVisibility(
    animatesHiddenEdgeContentInset: Bool = false
  ) {
    guard collectionView != nil else { return }

    setAccessoryDisplayItem(
      .prependLoader,
      visible: prependTrigger.loader != nil,
      positionPreservation: .itemsAfterMutation,
      completion: { [weak self] in
        guard let self else { return }
        self.reconfigureAccessoryDisplayItem(.prependLoader)
        self.remeasureAccessoryDisplayItem(.prependLoader, positionPreservation: .itemsAfterMutation)

        self.setAccessoryDisplayItem(
          .appendLoader,
          visible: self.appendTrigger.loader != nil,
          positionPreservation: .itemsBeforeMutation,
          completion: { [weak self] in
            guard let self else { return }
            self.reconfigureAccessoryDisplayItem(.appendLoader)
            self.remeasureAccessoryDisplayItem(.appendLoader, positionPreservation: .itemsBeforeMutation)
            self.updateHiddenEdgeContentInset(animated: animatesHiddenEdgeContentInset)
          }
        )
      }
    )
  }

  private func scheduleTypingIndicatorVisiblePhase() {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      guard self.displayedAccessoryState.hasTypingIndicator else { return }
      guard self.typingIndicator?.isVisible == true else { return }
      guard !self.isAnimatingTypingIndicatorRemoval else { return }

      self.typingIndicatorPhase = .visible
      self.reconfigureAccessoryDisplayItem(.typingIndicator)
      self.remeasureAccessoryDisplayItem(.typingIndicator, positionPreservation: .itemsBeforeMutation)
      self.updateHiddenEdgeContentInset()
    }
  }

  private func finishTypingIndicatorRemoval(
    generation: UInt,
    clampAnimated: Bool
  ) {
    guard isAnimatingTypingIndicatorRemoval else { return }
    guard typingIndicatorRemovalGeneration == generation else { return }

    typingIndicatorRemovalWorkItem?.cancel()
    typingIndicatorRemovalWorkItem = nil
    isAnimatingTypingIndicatorRemoval = false
    isTypingIndicatorIncludedInContentBounds = false
    reconfigureAccessoryDisplayItem(.typingIndicator)
    remeasureAccessoryDisplayItem(.typingIndicator, positionPreservation: .itemsBeforeMutation)
    updateHiddenEdgeContentInset()
    collectionView.layoutIfNeeded()
    clampContentOffsetToScrollableBounds(animated: clampAnimated)
  }

  private func scheduleTypingIndicatorRemovalCompletion(
    generation: UInt,
    clampAnimated: Bool,
    delay: TimeInterval
  ) {
    typingIndicatorRemovalWorkItem?.cancel()

    let workItem = DispatchWorkItem { [weak self] in
      self?.finishTypingIndicatorRemoval(
        generation: generation,
        clampAnimated: clampAnimated
      )
    }
    typingIndicatorRemovalWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
  }

  private func updateTypingIndicatorVisibility() {
    let isVisible = typingIndicator?.isVisible ?? false
    let wasNearBottom = collectionView.tiledScrollGeometry.pointsFromBottom < 100

    guard typingIndicator != nil else {
      typingIndicatorRemovalGeneration &+= 1
      typingIndicatorRemovalWorkItem?.cancel()
      typingIndicatorRemovalWorkItem = nil
      isAnimatingTypingIndicatorRemoval = false
      isTypingIndicatorIncludedInContentBounds = false

      setAccessoryDisplayItem(
        .typingIndicator,
        visible: false,
        positionPreservation: .itemsBeforeMutation,
        completion: { [weak self] in
          self?.updateHiddenEdgeContentInset()
        }
      )
      return
    }

    if isAnimatingTypingIndicatorRemoval {
      guard isVisible else { return }
      typingIndicatorRemovalGeneration &+= 1
      typingIndicatorRemovalWorkItem?.cancel()
      typingIndicatorRemovalWorkItem = nil
      isAnimatingTypingIndicatorRemoval = false
      isTypingIndicatorIncludedInContentBounds = true
      typingIndicatorPhase = .appearing
      springAnimator?.stop(finished: false)
      springAnimator = nil
      reconfigureAccessoryDisplayItem(.typingIndicator)
      remeasureAccessoryDisplayItem(.typingIndicator, positionPreservation: .itemsBeforeMutation)
      updateHiddenEdgeContentInset()
      if wasNearBottom {
        collectionView.layoutIfNeeded()
        scrollTo(edge: .bottom, animated: true)
      }
      scheduleTypingIndicatorVisiblePhase()
      return
    }

    if isTypingIndicatorIncludedInContentBounds && !isVisible {
      collectionView.layoutIfNeeded()
      typingIndicatorRemovalGeneration &+= 1
      let removalGeneration = typingIndicatorRemovalGeneration
      typingIndicatorRemovalWorkItem?.cancel()
      typingIndicatorRemovalWorkItem = nil
      isAnimatingTypingIndicatorRemoval = true
      typingIndicatorPhase = .dismissing
      reconfigureAccessoryDisplayItem(.typingIndicator)

      guard wasNearBottom else {
        scheduleTypingIndicatorRemovalCompletion(
          generation: removalGeneration,
          clampAnimated: true,
          delay: typingIndicatorRemovalDelay
        )
        return
      }

      guard let indexPath = indexPath(for: .typingIndicator),
            let attributes = tiledLayout.layoutAttributesForItem(at: indexPath) else {
        finishTypingIndicatorRemoval(
          generation: removalGeneration,
          clampAnimated: false
        )
        return
      }

      let scrollableBounds = scrollableContentOffsetBounds()
      let targetOffsetY = max(scrollableBounds.min, scrollableBounds.max - attributes.frame.height)
      scheduleTypingIndicatorRemovalCompletion(
        generation: removalGeneration,
        clampAnimated: false,
        delay: typingIndicatorRemovalAnimationDuration
      )

      scrollToContentOffsetY(
        targetOffsetY,
        animated: true,
        spring: Spring(duration: typingIndicatorRemovalAnimationDuration, bounce: 0)
      ) { [weak self] in
        self?.finishTypingIndicatorRemoval(
          generation: removalGeneration,
          clampAnimated: false
        )
      }
      return
    }

    setAccessoryDisplayItem(
      .typingIndicator,
      visible: true,
      positionPreservation: .itemsBeforeMutation,
      completion: { [weak self] in
        guard let self else { return }

        if isVisible {
          if !self.isTypingIndicatorIncludedInContentBounds {
            self.isTypingIndicatorIncludedInContentBounds = true
            self.typingIndicatorPhase = .appearing
          }

          self.reconfigureAccessoryDisplayItem(.typingIndicator)
          self.remeasureAccessoryDisplayItem(.typingIndicator, positionPreservation: .itemsBeforeMutation)
          self.updateHiddenEdgeContentInset()

          if wasNearBottom {
            self.collectionView.layoutIfNeeded()
            self.scrollTo(edge: .bottom, animated: true)
          }

          self.scheduleTypingIndicatorVisiblePhase()
        } else {
          self.typingIndicatorPhase = .dismissing
          self.reconfigureAccessoryDisplayItem(.typingIndicator)
          self.remeasureAccessoryDisplayItem(.typingIndicator, positionPreservation: .itemsBeforeMutation)
          self.updateHiddenEdgeContentInset()
        }
      }
    )
  }

  private func updateHeaderContentVisibility() {
    guard collectionView != nil else { return }

    setAccessoryDisplayItem(
      .headerContent,
      visible: headerContent != nil,
      positionPreservation: .itemsAfterMutation
    )
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
  TypingIndicatorContent: View,
  HeaderContentView: View,
  StateValue
>: UIViewRepresentable {

  typealias UIViewType = TiledUIView<Item, Cell, PrependLoadingView, AppendLoadingView, TypingIndicatorContent, HeaderContentView, StateValue>

  let items: [Item]
  let makeInitialState: (Item) -> StateValue
  let cellBuilder: (Item, CellReveal?, CellStateStorage<StateValue>) -> Cell
  let onTiledScrollGeometryChange: ((TiledScrollGeometry) -> Void)?
  let onTapBackground: (() -> Void)?
  let onDragIntoBottomSafeArea: (() -> Void)?
  let additionalContentInset: EdgeInsets
  let swiftUIWorldSafeAreaInset: EdgeInsets
  let revealConfiguration: RevealConfiguration
  let prependLoader: Loader<PrependLoadingView>?
  let appendLoader: Loader<AppendLoadingView>?
  let typingIndicator: TypingIndicator<TypingIndicatorContent>?
  let headerContent: HeaderContent<HeaderContentView>?
  @Binding var scrollPosition: TiledScrollPosition

  init(
    items: [Item],
    scrollPosition: Binding<TiledScrollPosition>,
    makeInitialState: @escaping (Item) -> StateValue,
    onTiledScrollGeometryChange: ((TiledScrollGeometry) -> Void)? = nil,
    onTapBackground: (() -> Void)? = nil,
    onDragIntoBottomSafeArea: (() -> Void)? = nil,
    additionalContentInset: EdgeInsets = .init(),
    swiftUIWorldSafeAreaInset: EdgeInsets = .init(),
    revealConfiguration: RevealConfiguration = .default,
    prependLoader: Loader<PrependLoadingView>?,
    appendLoader: Loader<AppendLoadingView>?,
    typingIndicator: TypingIndicator<TypingIndicatorContent>?,
    headerContent: HeaderContent<HeaderContentView>?,
    cellBuilder: @escaping (Item, CellReveal?, CellStateStorage<StateValue>) -> Cell
  ) {
    self.items = items
    self._scrollPosition = scrollPosition
    self.makeInitialState = makeInitialState
    self.onTiledScrollGeometryChange = onTiledScrollGeometryChange
    self.onTapBackground = onTapBackground
    self.onDragIntoBottomSafeArea = onDragIntoBottomSafeArea
    self.additionalContentInset = additionalContentInset
    self.swiftUIWorldSafeAreaInset = swiftUIWorldSafeAreaInset
    self.revealConfiguration = revealConfiguration
    self.prependLoader = prependLoader
    self.appendLoader = appendLoader
    self.typingIndicator = typingIndicator
    self.headerContent = headerContent
    self.cellBuilder = cellBuilder
  }

  func makeUIView(context: Context) -> UIViewType {
    let view = UIViewType(makeInitialState: makeInitialState, cellBuilder: cellBuilder)
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

    // Update loaders, typing indicator, and header content
    uiView.setLoaders(prepend: prependLoader, append: appendLoader)
    uiView.setTypingIndicator(typingIndicator)
    uiView.setHeaderContent(headerContent)

    uiView.applyItems(items)
    uiView.applyScrollPosition(scrollPosition)
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
///             └── TiledUIView (UIView)
///                     ├── UICollectionView
///                     │       └── TiledViewCell (UIHostingConfiguration)
///                     └── TiledCollectionViewLayout (Custom Layout)
/// ```
///
/// ## Basic Usage
///
/// ```swift
/// struct ChatView: View {
///   @State private var messages: [Message] = []
///   @State private var scrollPosition = TiledScrollPosition()
///
///   var body: some View {
///     TiledView(
///       items: messages,
///       scrollPosition: $scrollPosition
///     ) { message in
///       MessageBubbleCell(item: message)
///     }
///     .prependLoader(.loader(perform: { await store.loadOlder() }) {
///       ProgressView()
///     })
///     .typingIndicator(.indicator(isVisible: store.isTyping) {
///       TypingBubbleView()
///     })
///     .headerContent(.header {
///       Text("Start of conversation")
///     })
///     .onAppear {
///       messages = initialMessages
///     }
///   }
/// }
/// ```
///
/// ## Auxiliary Content
///
/// Loaders, typing indicator, and header content are configured via modifiers.
/// Each modifier can only be called once (enforced by generic constraints).
///
/// - `.prependLoader(_:)` — Loading indicator at top for loading older items
/// - `.appendLoader(_:)` — Loading indicator at bottom for loading newer items
/// - `.typingIndicator(_:)` — Typing indicator shown below the last message
/// - `.headerContent(_:)` — Static header between prepend loader and first item
///
/// ## Items
///
/// Use a plain `[Item]` as the source of truth. TiledView compares the currently
/// displayed items with the new snapshot and applies the appropriate changes.
///
/// ```swift
/// messages = latestMessages
/// messages.insert(contentsOf: olderMessages, at: 0)
/// messages.append(newMessage)
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
/// TiledView(items: messages, scrollPosition: $scrollPosition) { item, state in
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
/// Use `.prependLoader()` modifier to load older content when scrolling near top:
///
/// ```swift
/// TiledView(items: messages, scrollPosition: $scrollPosition) { message in
///   MessageBubbleCell(item: message)
/// }
/// .prependLoader(.loader(perform: {
///   let olderMessages = await api.fetchOlderMessages()
///   messages.insert(contentsOf: olderMessages, at: 0)
/// }) {
///   ProgressView()
/// })
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
  TypingIndicatorContent: View,
  HeaderContentView: View,
  StateValue
>: View {

  let items: [Item]
  let makeInitialState: (Item) -> StateValue
  let cellBuilder: (Item, CellReveal?, CellStateStorage<StateValue>) -> Cell
  var onTiledScrollGeometryChange: ((TiledScrollGeometry) -> Void)?
  var onTapBackground: (() -> Void)?
  var onDragIntoBottomSafeArea: (() -> Void)?
  var additionalContentInset: EdgeInsets = .init()
  var revealConfiguration: RevealConfiguration = .default
  let prependLoader: Loader<PrependLoadingView>?
  let appendLoader: Loader<AppendLoadingView>?
  let typingIndicator: TypingIndicator<TypingIndicatorContent>?
  let headerContent: HeaderContent<HeaderContentView>?
  @Binding var scrollPosition: TiledScrollPosition

  /// Internal initializer for creating TiledView with all parameters (used by modifiers)
  init(
    items: [Item],
    makeInitialState: @escaping (Item) -> StateValue,
    cellBuilder: @escaping (Item, CellReveal?, CellStateStorage<StateValue>) -> Cell,
    onTiledScrollGeometryChange: ((TiledScrollGeometry) -> Void)?,
    onTapBackground: (() -> Void)?,
    onDragIntoBottomSafeArea: (() -> Void)?,
    additionalContentInset: EdgeInsets,
    revealConfiguration: RevealConfiguration,
    prependLoader: Loader<PrependLoadingView>?,
    appendLoader: Loader<AppendLoadingView>?,
    typingIndicator: TypingIndicator<TypingIndicatorContent>?,
    headerContent: HeaderContent<HeaderContentView>?,
    scrollPosition: Binding<TiledScrollPosition>
  ) {
    self.items = items
    self.makeInitialState = makeInitialState
    self.cellBuilder = cellBuilder
    self.onTiledScrollGeometryChange = onTiledScrollGeometryChange
    self.onTapBackground = onTapBackground
    self.onDragIntoBottomSafeArea = onDragIntoBottomSafeArea
    self.additionalContentInset = additionalContentInset
    self.revealConfiguration = revealConfiguration
    self.prependLoader = prependLoader
    self.appendLoader = appendLoader
    self.typingIndicator = typingIndicator
    self.headerContent = headerContent
    self._scrollPosition = scrollPosition
  }
}

// MARK: - Public Initializers

extension TiledView where PrependLoadingView == Never, AppendLoadingView == Never, TypingIndicatorContent == Never, HeaderContentView == Never {

  /// Creates a TiledView.
  ///
  /// Add auxiliary content using modifiers:
  /// ```swift
  /// TiledView(
  ///   items: messages,
  ///   scrollPosition: $scrollPosition,
  ///   makeInitialState: { _ in 0 }
  /// ) { message in
  ///   MessageBubbleCell(item: message)
  /// }
  /// .prependLoader(.loader(perform: { await store.loadOlder() }) { ProgressView() })
  /// .typingIndicator(.indicator(isVisible: store.isTyping) { TypingBubbleView() })
  /// .headerContent(.header { Text("Start of conversation") })
  /// ```
  ///
  /// - Parameters:
  ///   - items: The items to display.
  ///   - scrollPosition: Binding to control scroll position.
  ///   - makeInitialState: A closure that creates the initial state for each item.
  ///   - cellBuilder: A closure that returns a `TiledCellContent` for each item.
  public init<CellContent: TiledCellContent>(
    items: [Item],
    scrollPosition: Binding<TiledScrollPosition>,
    makeInitialState: @escaping (Item) -> StateValue,
    cellBuilder: @escaping (Item) -> CellContent
  ) where Cell == TiledCellContentWrapper<CellContent>, StateValue == CellContent.StateValue {
    self.items = items
    self._scrollPosition = scrollPosition
    self.makeInitialState = makeInitialState
    self.prependLoader = nil
    self.appendLoader = nil
    self.typingIndicator = nil
    self.headerContent = nil
    self.cellBuilder = { item, cellReveal, storage in
      TiledCellContentWrapper(
        content: cellBuilder(item),
        cellReveal: cellReveal,
        state: storage
      )
    }
  }

}

extension TiledView where StateValue == Void, PrependLoadingView == Never, AppendLoadingView == Never, TypingIndicatorContent == Never, HeaderContentView == Never {

  /// Creates a TiledView without per-cell state.
  ///
  /// Convenience initializer where `makeInitialState` defaults to `{ _ in () }`.
  public init<CellContent: TiledCellContent>(
    items: [Item],
    scrollPosition: Binding<TiledScrollPosition>,
    cellBuilder: @escaping (Item) -> CellContent
  ) where Cell == TiledCellContentWrapper<CellContent>, CellContent.StateValue == Void {
    self.init(
      items: items,
      scrollPosition: scrollPosition,
      makeInitialState: { _ in () },
      cellBuilder: cellBuilder
    )
  }

}

// MARK: - Auxiliary Content Modifiers

extension TiledView where PrependLoadingView == Never {

  /// Adds a prepend loader (loading indicator at top for loading older items).
  public consuming func prependLoader<V: View>(
    _ loader: Loader<V>?
  ) -> TiledView<Item, Cell, V, AppendLoadingView, TypingIndicatorContent, HeaderContentView, StateValue> {
    .init(
      items: items,
      makeInitialState: makeInitialState,
      cellBuilder: cellBuilder,
      onTiledScrollGeometryChange: onTiledScrollGeometryChange,
      onTapBackground: onTapBackground,
      onDragIntoBottomSafeArea: onDragIntoBottomSafeArea,
      additionalContentInset: additionalContentInset,
      revealConfiguration: revealConfiguration,
      prependLoader: loader,
      appendLoader: appendLoader,
      typingIndicator: typingIndicator,
      headerContent: headerContent,
      scrollPosition: $scrollPosition
    )
  }
}

extension TiledView where AppendLoadingView == Never {

  /// Adds an append loader (loading indicator at bottom for loading newer items).
  public consuming func appendLoader<V: View>(
    _ loader: Loader<V>?
  ) -> TiledView<Item, Cell, PrependLoadingView, V, TypingIndicatorContent, HeaderContentView, StateValue> {
    .init(
      items: items,
      makeInitialState: makeInitialState,
      cellBuilder: cellBuilder,
      onTiledScrollGeometryChange: onTiledScrollGeometryChange,
      onTapBackground: onTapBackground,
      onDragIntoBottomSafeArea: onDragIntoBottomSafeArea,
      additionalContentInset: additionalContentInset,
      revealConfiguration: revealConfiguration,
      prependLoader: prependLoader,
      appendLoader: loader,
      typingIndicator: typingIndicator,
      headerContent: headerContent,
      scrollPosition: $scrollPosition
    )
  }
}

extension TiledView where TypingIndicatorContent == Never {

  /// Adds a typing indicator (shown at bottom when other users are typing).
  public consuming func typingIndicator<V: View>(
    _ indicator: TypingIndicator<V>?
  ) -> TiledView<Item, Cell, PrependLoadingView, AppendLoadingView, V, HeaderContentView, StateValue> {
    .init(
      items: items,
      makeInitialState: makeInitialState,
      cellBuilder: cellBuilder,
      onTiledScrollGeometryChange: onTiledScrollGeometryChange,
      onTapBackground: onTapBackground,
      onDragIntoBottomSafeArea: onDragIntoBottomSafeArea,
      additionalContentInset: additionalContentInset,
      revealConfiguration: revealConfiguration,
      prependLoader: prependLoader,
      appendLoader: appendLoader,
      typingIndicator: indicator,
      headerContent: headerContent,
      scrollPosition: $scrollPosition
    )
  }
}

extension TiledView where HeaderContentView == Never {

  /// Adds a static header content between the prepend loader and the first message.
  public consuming func headerContent<V: View>(
    _ header: HeaderContent<V>?
  ) -> TiledView<Item, Cell, PrependLoadingView, AppendLoadingView, TypingIndicatorContent, V, StateValue> {
    .init(
      items: items,
      makeInitialState: makeInitialState,
      cellBuilder: cellBuilder,
      onTiledScrollGeometryChange: onTiledScrollGeometryChange,
      onTapBackground: onTapBackground,
      onDragIntoBottomSafeArea: onDragIntoBottomSafeArea,
      additionalContentInset: additionalContentInset,
      revealConfiguration: revealConfiguration,
      prependLoader: prependLoader,
      appendLoader: appendLoader,
      typingIndicator: typingIndicator,
      headerContent: header,
      scrollPosition: $scrollPosition
    )
  }
}

// MARK: - View Body and Basic Modifiers

extension TiledView {

  public var body: some View {
    GeometryReader { proxy in
      TiledViewRepresentable(
        items: items,
        scrollPosition: $scrollPosition,
        makeInitialState: makeInitialState,
        onTiledScrollGeometryChange: onTiledScrollGeometryChange,
        onTapBackground: onTapBackground,
        onDragIntoBottomSafeArea: onDragIntoBottomSafeArea,
        additionalContentInset: additionalContentInset,
        swiftUIWorldSafeAreaInset: proxy.safeAreaInsets,
        revealConfiguration: revealConfiguration,
        prependLoader: prependLoader,
        appendLoader: appendLoader,
        typingIndicator: typingIndicator,
        headerContent: headerContent,
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
