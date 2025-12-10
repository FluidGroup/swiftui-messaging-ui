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

  public func configure<Content: View>(with content: Content) {
    contentConfiguration = UIHostingConfiguration {
      content
    }
    .margins(.all, 0)
  }

  public override func prepareForReuse() {
    super.prepareForReuse()
    contentConfiguration = nil
  }

  public override func preferredLayoutAttributesFitting(
    _ layoutAttributes: UICollectionViewLayoutAttributes
  ) -> UICollectionViewLayoutAttributes {
    let attributes = layoutAttributes.copy() as! UICollectionViewLayoutAttributes

    // UIHostingConfigurationを使用している場合、systemLayoutSizeFittingでサイズを取得
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

// MARK: - TiledView

public final class TiledView<Item: Identifiable & Equatable, Cell: View>: UIView, UICollectionViewDataSource, UICollectionViewDelegate {

  private var collectionView: UICollectionView!
  private var tiledLayout: TiledCollectionViewLayout!

  private var items: [Item] = []
  private let cellBuilder: (Item) -> Cell

  /// サイズ計測用のCell（再利用）
  private lazy var sizingCell = TiledViewCell()

  /// DataSource tracking
  private var lastDataSourceID: UUID?
  private var appliedCursor: Int = 0

  public var onPrepend: (() -> Void)?
  public var onAppend: (() -> Void)?

  public init(
    cellBuilder: @escaping (Item) -> Cell
  ) {
    self.cellBuilder = cellBuilder
    super.init(frame: .zero)
    setupCollectionView()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupCollectionView() {
    tiledLayout = TiledCollectionViewLayout()
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

    collectionView.register(TiledViewCell.self, forCellWithReuseIdentifier: TiledViewCell.reuseIdentifier)

    addSubview(collectionView)

    NSLayoutConstraint.activate([
      collectionView.topAnchor.constraint(equalTo: topAnchor),
      collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
      collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
      collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  private func measureSize(at index: Int, width: CGFloat) -> CGSize? {
    guard index < items.count else { return nil }
    let item = items[index]

    // UIHostingConfigurationと同じ方法で計測
    sizingCell.configure(with: cellBuilder(item))
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

  private func centerOnItems() {
    guard let firstY = tiledLayout.firstItemY() else { return }
    collectionView.contentOffset = CGPoint(x: 0, y: firstY - 100)
  }

  public func setItems(_ newItems: [Item]) {
    tiledLayout.clear()
    items = newItems
    tiledLayout.appendItems(count: newItems.count, startingIndex: 0)
    collectionView.reloadData()

    DispatchQueue.main.async { [weak self] in
      self?.centerOnItems()
    }
  }

  public func prependItems(_ newItems: [Item]) {
    items.insert(contentsOf: newItems, at: 0)
    tiledLayout.prependItems(count: newItems.count)
    collectionView.reloadData()
    collectionView.invalidateIntrinsicContentSize()
    collectionView.layoutIfNeeded()
  }

  public func appendItems(_ newItems: [Item]) {
    let startingIndex = items.count
    items.append(contentsOf: newItems)
    tiledLayout.appendItems(count: newItems.count, startingIndex: startingIndex)
    collectionView.reloadData()
    collectionView.layoutIfNeeded()
  }

  // MARK: - DataSource-based API

  /// Applies changes from a TiledDataSource.
  /// Uses cursor tracking to apply only new changes since last application.
  public func applyDataSource(_ dataSource: TiledDataSource<Item>) {
    // Check if this is a new DataSource instance
    if lastDataSourceID != dataSource.id {
      lastDataSourceID = dataSource.id
      appliedCursor = 0
      tiledLayout.clear()
      items = []
    }

    // Apply only changes after the cursor
    let pendingChanges = dataSource.pendingChanges
    guard appliedCursor < pendingChanges.count else { return }

    let newChanges = pendingChanges[appliedCursor...]
    for change in newChanges {
      applyChange(change)
    }
    appliedCursor = pendingChanges.count
  }

  private func applyChange(_ change: TiledDataSource<Item>.Change) {
    switch change {
    case .setItems(let newItems):
      tiledLayout.clear()
      items = newItems
      tiledLayout.appendItems(count: newItems.count, startingIndex: 0)
      collectionView.reloadData()

    case .prepend(let newItems):
      items.insert(contentsOf: newItems, at: 0)
      tiledLayout.prependItems(count: newItems.count)
      collectionView.reloadData()

    case .append(let newItems):
      let startingIndex = items.count
      items.append(contentsOf: newItems)
      tiledLayout.appendItems(count: newItems.count, startingIndex: startingIndex)
      collectionView.reloadData()

    case .update(let updatedItems):
      for item in updatedItems {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
          items[index] = item
        }
      }
      collectionView.reloadData()

    case .remove(let ids):
      let idsSet = Set(ids.map { AnyHashable($0) })
      items.removeAll { idsSet.contains(AnyHashable($0.id)) }
      // TODO: Update layout to handle removal
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
    cell.configure(with: cellBuilder(item))
    return cell
  }

  // MARK: UICollectionViewDelegate

  public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    // Override in subclass or use closure if needed
  }
}

// MARK: - TiledViewRepresentable

public struct TiledViewRepresentable<Item: Identifiable & Equatable, Cell: View>: UIViewRepresentable {

  public typealias UIViewType = TiledView<Item, Cell>

  let dataSource: TiledDataSource<Item>
  let cellBuilder: (Item) -> Cell

  public init(
    dataSource: TiledDataSource<Item>,
    @ViewBuilder cellBuilder: @escaping (Item) -> Cell
  ) {
    self.dataSource = dataSource
    self.cellBuilder = cellBuilder
  }

  public func makeUIView(context: Context) -> TiledView<Item, Cell> {
    let view = TiledView(cellBuilder: cellBuilder)
    view.applyDataSource(dataSource)
    return view
  }

  public func updateUIView(_ uiView: TiledView<Item, Cell>, context: Context) {
    uiView.applyDataSource(dataSource)
  }
}
