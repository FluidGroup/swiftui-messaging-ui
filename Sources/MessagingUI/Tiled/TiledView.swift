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

  private var hostingController: UIHostingController<AnyView>?

  public func configure<Content: View>(with content: Content) {
    contentConfiguration = UIHostingConfiguration {
      content
    }
    .margins(.all, 0)
  }

  public override func prepareForReuse() {
    super.prepareForReuse()
    hostingController = nil
  }
}

// MARK: - TiledView

public final class TiledView<Item: Identifiable, Cell: View>: UIView, UICollectionViewDataSource, UICollectionViewDelegate {

  private var collectionView: UICollectionView!
  private var tiledLayout: TiledCollectionViewLayout!

  private var items: [Item] = []
  private let cellBuilder: (Item) -> Cell
  private let heightCalculator: (Item, CGFloat) -> CGFloat

  public var onPrepend: (() -> Void)?
  public var onAppend: (() -> Void)?

  public init(
    cellBuilder: @escaping (Item) -> Cell,
    heightCalculator: @escaping (Item, CGFloat) -> CGFloat
  ) {
    self.cellBuilder = cellBuilder
    self.heightCalculator = heightCalculator
    super.init(frame: .zero)
    setupCollectionView()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupCollectionView() {
    tiledLayout = TiledCollectionViewLayout()

    collectionView = UICollectionView(frame: .zero, collectionViewLayout: tiledLayout)
    collectionView.translatesAutoresizingMaskIntoConstraints = false
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

  private func centerOnItems() {
    guard let firstY = tiledLayout.firstItemY() else { return }
    collectionView.contentOffset = CGPoint(x: 0, y: firstY - 100)
  }

  public func setItems(_ newItems: [Item]) {
    let width = collectionView.bounds.width > 0 ? collectionView.bounds.width : 375
    let heights = newItems.map { heightCalculator($0, width) }
    tiledLayout.clear()
    tiledLayout.appendItems(heights: heights)
    items = newItems
    collectionView.reloadData()

    DispatchQueue.main.async { [weak self] in
      self?.centerOnItems()
    }
  }

  public func prependItems(_ newItems: [Item]) {
    let width = collectionView.bounds.width > 0 ? collectionView.bounds.width : 375
    let heights = newItems.map { heightCalculator($0, width) }
    tiledLayout.prependItems(heights: heights)

    items.insert(contentsOf: newItems, at: 0)
    collectionView.reloadData()
  }

  public func appendItems(_ newItems: [Item]) {
    let width = collectionView.bounds.width > 0 ? collectionView.bounds.width : 375
    let heights = newItems.map { heightCalculator($0, width) }
    tiledLayout.appendItems(heights: heights)

    items.append(contentsOf: newItems)
    collectionView.reloadData()
  }

  public func updateItemHeight(at index: Int, newHeight: CGFloat) {
    tiledLayout.updateItemHeight(at: index, newHeight: newHeight)
    collectionView.reloadData()
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

public struct TiledViewRepresentable<Item: Identifiable, Cell: View>: UIViewRepresentable {

  public typealias UIViewType = TiledView<Item, Cell>

  @Binding var tiledView: TiledView<Item, Cell>?
  let items: [Item]
  let cellBuilder: (Item) -> Cell
  let heightCalculator: (Item, CGFloat) -> CGFloat

  public init(
    tiledView: Binding<TiledView<Item, Cell>?>,
    items: [Item],
    @ViewBuilder cellBuilder: @escaping (Item) -> Cell,
    heightCalculator: @escaping (Item, CGFloat) -> CGFloat
  ) {
    self._tiledView = tiledView
    self.items = items
    self.cellBuilder = cellBuilder
    self.heightCalculator = heightCalculator
  }

  public func makeUIView(context: Context) -> TiledView<Item, Cell> {
    let view = TiledView(cellBuilder: cellBuilder, heightCalculator: heightCalculator)
    DispatchQueue.main.async {
      tiledView = view
    }
    return view
  }

  public func updateUIView(_ uiView: TiledView<Item, Cell>, context: Context) {
    // Items are managed externally via tiledView reference
  }
}
