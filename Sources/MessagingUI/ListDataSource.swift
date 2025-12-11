//
//  ListDataSource.swift
//  MessagingUI
//
//  Created by Hiroshi Kimura on 2025/12/10.
//

import DequeModule
import Foundation

// MARK: - ListDataSource

/// A data source that tracks changes for efficient list updates.
///
/// Instead of directly modifying an array, use this data source's methods
/// to modify items. This allows list views to know exactly what changed
/// and update accordingly without adjusting content offset.
public struct ListDataSource<Item: Identifiable & Equatable>: Equatable {

  // MARK: - Change

  public enum Change: Equatable {
    case setItems
    case prepend([Item.ID])
    case append([Item.ID])
    case insert(at: Int, ids: [Item.ID])
    case update([Item.ID])
    case remove([Item.ID])
  }

  // MARK: - Properties

  /// Unique identifier for this data source instance.
  /// Used by TiledView to detect when the data source is replaced.
  public let id: UUID = UUID()

  /// Change counter used as cursor for tracking applied changes.
  public private(set) var changeCounter: Int = 0

  /// Internal storage using Deque for efficient prepend operations.
  private var _items: Deque<Item> = []

  /// The current items in the data source.
  public var items: [Item] { Array(_items) }

  /// Pending changes that haven't been consumed by TiledView yet.
  internal private(set) var pendingChanges: [Change] = []

  // MARK: - Initializers

  public init() {}

  public init(items: [Item]) {
    self._items = Deque(items)
    self.pendingChanges = [.setItems]
    self.changeCounter = 1
  }

  // MARK: - Mutation Methods

  /// Sets all items, replacing any existing items.
  /// Use this for initial load or complete refresh.
  public mutating func setItems(_ items: [Item]) {
    self._items = Deque(items)
    pendingChanges.append(.setItems)
    changeCounter += 1
  }

  /// Adds items to the beginning of the list.
  /// Use this for loading older content (e.g., older messages).
  public mutating func prepend(_ items: [Item]) {
    guard !items.isEmpty else { return }
    let ids = items.map { $0.id }
    for item in items.reversed() {
      self._items.prepend(item)
    }
    pendingChanges.append(.prepend(ids))
    changeCounter += 1
  }

  /// Adds items to the end of the list.
  /// Use this for loading newer content (e.g., new messages).
  public mutating func append(_ items: [Item]) {
    guard !items.isEmpty else { return }
    let ids = items.map { $0.id }
    self._items.append(contentsOf: items)
    pendingChanges.append(.append(ids))
    changeCounter += 1
  }

  /// Inserts items at a specific index.
  /// Use this for middle insertions (not at beginning or end).
  public mutating func insert(_ items: [Item], at index: Int) {
    guard !items.isEmpty else { return }
    let ids = items.map { $0.id }
    for (offset, item) in items.enumerated() {
      self._items.insert(item, at: index + offset)
    }
    pendingChanges.append(.insert(at: index, ids: ids))
    changeCounter += 1
  }

  /// Updates existing items by matching their IDs.
  /// Items that don't exist in the current list are ignored.
  public mutating func update(_ items: [Item]) {
    guard !items.isEmpty else { return }
    var updatedIds: [Item.ID] = []
    for item in items {
      if let index = self._items.firstIndex(where: { $0.id == item.id }) {
        self._items[index] = item
        updatedIds.append(item.id)
      }
    }
    if !updatedIds.isEmpty {
      pendingChanges.append(.update(updatedIds))
      changeCounter += 1
    }
  }

  /// Removes items with the specified IDs.
  public mutating func remove(ids: [Item.ID]) {
    guard !ids.isEmpty else { return }
    let idsSet = Set(ids)
    let removedIds = _items.filter { idsSet.contains($0.id) }.map { $0.id }
    self._items.removeAll { idsSet.contains($0.id) }
    if !removedIds.isEmpty {
      pendingChanges.append(.remove(removedIds))
      changeCounter += 1
    }
  }

  /// Removes a single item with the specified ID.
  public mutating func remove(id: Item.ID) {
    remove(ids: [id])
  }

  // MARK: - Equatable

  public static func == (lhs: ListDataSource<Item>, rhs: ListDataSource<Item>) -> Bool {
    // Compare id and items, not pendingChanges or changeCounter
    // Different id means different data source instance
    lhs.id == rhs.id && lhs.items == rhs.items
  }
}

extension ListDataSource {

  /// Removes items with the specified IDs (optimized for Hashable IDs).
  public mutating func remove(ids: Set<Item.ID>) {
    guard !ids.isEmpty else { return }
    let removedIds = _items.filter { ids.contains($0.id) }.map { $0.id }
    self._items.removeAll { ids.contains($0.id) }
    if !removedIds.isEmpty {
      pendingChanges.append(.remove(removedIds))
      changeCounter += 1
    }
  }

  /// Applies the difference between current items and new items.
  /// Automatically detects prepend, append, insert, update, and remove operations.
  public mutating func applyDiff(from newItems: [Item]) {
    let oldItems = self.items

    // Empty to non-empty: use setItems
    if oldItems.isEmpty && !newItems.isEmpty {
      setItems(newItems)
      return
    }

    // Non-empty to empty: remove all
    if !oldItems.isEmpty && newItems.isEmpty {
      remove(ids: Set(oldItems.map { $0.id }))
      return
    }

    // Both empty: nothing to do
    if oldItems.isEmpty && newItems.isEmpty {
      return
    }

    // Detect changes using Swift's difference API
    let oldIDs = oldItems.map { $0.id }
    let newIDs = newItems.map { $0.id }
    let diff = newIDs.difference(from: oldIDs)

    // Build indexed insertion and removal lists
    var insertions: [(offset: Int, id: Item.ID)] = []
    var removedIDsSet: Set<Item.ID> = []

    for change in diff {
      switch change {
      case .insert(let offset, let id, _):
        insertions.append((offset, id))
      case .remove(_, let id, _):
        removedIDsSet.insert(id)
      }
    }

    // Handle removals first
    if !removedIDsSet.isEmpty {
      remove(ids: removedIDsSet)
    }

    // Classify insertions by position
    let newItemsDict = Dictionary(uniqueKeysWithValues: newItems.map { ($0.id, $0) })
    let insertedIDsSet = Set(insertions.map { $0.id })

    // Find prepended items (consecutive from index 0)
    var prependedItems: [Item] = []
    for (index, id) in newIDs.enumerated() {
      if insertedIDsSet.contains(id), let item = newItemsDict[id] {
        if index == prependedItems.count {
          prependedItems.append(item)
        } else {
          break
        }
      } else {
        break
      }
    }

    // Find appended items (consecutive from the end)
    var appendedItems: [Item] = []
    let prependedIDsSet = Set(prependedItems.map { $0.id })
    for (index, id) in newIDs.enumerated().reversed() {
      if insertedIDsSet.contains(id) && !prependedIDsSet.contains(id),
         let item = newItemsDict[id] {
        if index == newIDs.count - 1 - appendedItems.count {
          appendedItems.insert(item, at: 0)
        } else {
          break
        }
      } else {
        break
      }
    }

    // Find middle insertions
    let appendedIDsSet = Set(appendedItems.map { $0.id })

    // Group consecutive middle insertions
    var middleInsertions: [(index: Int, items: [Item])] = []
    for (offset, id) in insertions {
      if prependedIDsSet.contains(id) || appendedIDsSet.contains(id) {
        continue
      }
      guard let item = newItemsDict[id] else { continue }

      // Adjust index for prepends already applied
      let adjustedIndex = offset - prependedItems.count

      if let lastGroup = middleInsertions.last,
         lastGroup.index + lastGroup.items.count == adjustedIndex {
        middleInsertions[middleInsertions.count - 1].items.append(item)
      } else {
        middleInsertions.append((adjustedIndex, [item]))
      }
    }

    // Apply changes in order
    if !prependedItems.isEmpty {
      prepend(prependedItems)
    }

    for (index, items) in middleInsertions {
      insert(items, at: index)
    }

    if !appendedItems.isEmpty {
      append(appendedItems)
    }

    // Detect updates (same ID, different content)
    let oldItemsDict = Dictionary(uniqueKeysWithValues: oldItems.map { ($0.id, $0) })
    var updatedItems: [Item] = []
    for newItem in newItems {
      if let oldItem = oldItemsDict[newItem.id], oldItem != newItem {
        updatedItems.append(newItem)
      }
    }

    if !updatedItems.isEmpty {
      update(updatedItems)
    }
  }
}

// MARK: - Backward Compatibility

/// Backward compatibility alias for TiledDataSource.
@available(*, deprecated, renamed: "ListDataSource")
public typealias TiledDataSource<Item: Identifiable & Equatable> = ListDataSource<Item>
