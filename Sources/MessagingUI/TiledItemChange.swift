//
//  TiledItemChange.swift
//  MessagingUI
//
//  Created by Hiroshi Kimura on 2025/12/10.
//

import DequeModule
import Foundation

// MARK: - TiledItemChange

/// Internal item snapshot diff used by TiledView.
///
/// Public callers should pass `[Item]` to `TiledView(items:scrollPosition:...)`.
/// TiledView translates item snapshots into these layout-preserving operations.
enum TiledItemChange<Item: Identifiable & Equatable>: Equatable {

  case replace([Item])
  case prepend([Item])
  case append([Item])
  case insert(at: Int, items: [Item])
  case update([Item])
  case remove([Item.ID])

  static func make(
    from oldItems: Deque<Item>,
    to newItems: [Item]
  ) -> [Self] {
    if oldItems.isEmpty && !newItems.isEmpty {
      return [.replace(newItems)]
    }

    if !oldItems.isEmpty && newItems.isEmpty {
      return [.remove(oldItems.map(\.id))]
    }

    if oldItems.isEmpty && newItems.isEmpty {
      return []
    }

    let oldIDs = oldItems.map(\.id)
    let newIDs = newItems.map(\.id)
    let diff = newIDs.difference(from: oldIDs)

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

    let newItemsByID = Dictionary(uniqueKeysWithValues: newItems.map { ($0.id, $0) })
    let insertedIDsSet = Set(insertions.map(\.id))

    var prependedItems: [Item] = []
    for (index, id) in newIDs.enumerated() {
      if insertedIDsSet.contains(id), let item = newItemsByID[id] {
        if index == prependedItems.count {
          prependedItems.append(item)
        } else {
          break
        }
      } else {
        break
      }
    }

    var appendedItems: [Item] = []
    let prependedIDsSet = Set(prependedItems.map(\.id))
    for (index, id) in newIDs.enumerated().reversed() {
      if insertedIDsSet.contains(id) && !prependedIDsSet.contains(id),
         let item = newItemsByID[id] {
        if index == newIDs.count - 1 - appendedItems.count {
          appendedItems.insert(item, at: 0)
        } else {
          break
        }
      } else {
        break
      }
    }

    let appendedIDsSet = Set(appendedItems.map(\.id))
    var middleInsertions: [(index: Int, items: [Item])] = []

    for (offset, id) in insertions {
      if prependedIDsSet.contains(id) || appendedIDsSet.contains(id) {
        continue
      }
      guard let item = newItemsByID[id] else { continue }

      let adjustedIndex = offset - prependedItems.count

      if let lastGroup = middleInsertions.last,
         lastGroup.index + lastGroup.items.count == adjustedIndex {
        middleInsertions[middleInsertions.count - 1].items.append(item)
      } else {
        middleInsertions.append((adjustedIndex, [item]))
      }
    }

    let oldItemsByID = Dictionary(uniqueKeysWithValues: oldItems.map { ($0.id, $0) })
    let updatedItems = newItems.compactMap { newItem -> Item? in
      guard let oldItem = oldItemsByID[newItem.id], oldItem != newItem else {
        return nil
      }
      return newItem
    }

    var changes: [Self] = []
    if !removedIDsSet.isEmpty {
      changes.append(.remove(Array(removedIDsSet)))
    }
    if !prependedItems.isEmpty {
      changes.append(.prepend(prependedItems))
    }
    for (index, items) in middleInsertions {
      changes.append(.insert(at: index, items: items))
    }
    if !appendedItems.isEmpty {
      changes.append(.append(appendedItems))
    }
    if !updatedItems.isEmpty {
      changes.append(.update(updatedItems))
    }
    return changes
  }
}
