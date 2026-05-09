//
//  TiledItemChangeTests.swift
//  MessagingUITests
//
//  Created by Hiroshi Kimura on 2025/12/12.
//

import DequeModule
import Testing
@testable import MessagingUI

struct TiledItemChangeTests {

  // MARK: - Test Item

  struct TestItem: Identifiable, Equatable {
    let id: Int
    var value: String
  }

  // MARK: - make Tests

  @Test
  func emptyToNonEmpty() {
    let newItems = [TestItem(id: 1, value: "A"), TestItem(id: 2, value: "B")]

    let changes = TiledItemChange.make(from: Deque<TestItem>(), to: newItems)

    #expect(changes == [.replace(newItems)])
  }

  @Test
  func nonEmptyToEmpty() {
    let oldItems = [TestItem(id: 1, value: "A")]

    let changes = TiledItemChange.make(from: Deque(oldItems), to: [])

    #expect(changes == [.remove([1])])
  }

  @Test
  func prependItems() {
    let oldItems = [TestItem(id: 2, value: "B")]
    let newItems = [TestItem(id: 1, value: "A"), TestItem(id: 2, value: "B")]

    let changes = TiledItemChange.make(from: Deque(oldItems), to: newItems)

    #expect(changes.contains(.prepend([TestItem(id: 1, value: "A")])))
  }

  @Test
  func appendItems() {
    let oldItems = [TestItem(id: 1, value: "A")]
    let newItems = [TestItem(id: 1, value: "A"), TestItem(id: 2, value: "B")]

    let changes = TiledItemChange.make(from: Deque(oldItems), to: newItems)

    #expect(changes.contains(.append([TestItem(id: 2, value: "B")])))
  }

  @Test
  func insertInMiddle() {
    let oldItems = [
      TestItem(id: 1, value: "A"),
      TestItem(id: 3, value: "C")
    ]
    let newItems = [
      TestItem(id: 1, value: "A"),
      TestItem(id: 2, value: "B"),
      TestItem(id: 3, value: "C")
    ]

    let changes = TiledItemChange.make(from: Deque(oldItems), to: newItems)

    #expect(changes.contains(.insert(at: 1, items: [TestItem(id: 2, value: "B")])))
  }

  @Test
  func updateItems() {
    let oldItems = [TestItem(id: 1, value: "A")]
    let newItems = [TestItem(id: 1, value: "A-Updated")]

    let changes = TiledItemChange.make(from: Deque(oldItems), to: newItems)

    #expect(changes.contains(.update([TestItem(id: 1, value: "A-Updated")])))
  }

  @Test
  func removeItems() {
    let oldItems = [
      TestItem(id: 1, value: "A"),
      TestItem(id: 2, value: "B")
    ]
    let newItems = [TestItem(id: 1, value: "A")]

    let changes = TiledItemChange.make(from: Deque(oldItems), to: newItems)

    #expect(changes.contains(.remove([2])))
  }

  @Test
  func complexOperation() {
    let oldItems = [
      TestItem(id: 2, value: "B"),
      TestItem(id: 3, value: "C"),
      TestItem(id: 4, value: "D")
    ]
    let newItems = [
      TestItem(id: 1, value: "A"),           // prepend
      TestItem(id: 2, value: "B-Updated"),   // update
      TestItem(id: 3, value: "C")            // unchanged
      // id: 4 removed
    ]

    let changes = TiledItemChange.make(from: Deque(oldItems), to: newItems)

    #expect(changes.contains(.remove([4])))
    #expect(changes.contains(.prepend([TestItem(id: 1, value: "A")])))
    #expect(changes.contains(.update([TestItem(id: 2, value: "B-Updated")])))
  }

  @Test
  func noChanges() {
    let items = [TestItem(id: 1, value: "A"), TestItem(id: 2, value: "B")]

    let changes = TiledItemChange.make(from: Deque(items), to: items)

    #expect(changes.isEmpty)
  }

  @Test
  func insertMultipleItems() {
    let oldItems = [
      TestItem(id: 1, value: "A"),
      TestItem(id: 4, value: "D")
    ]
    let newItems = [
      TestItem(id: 1, value: "A"),
      TestItem(id: 2, value: "B"),
      TestItem(id: 3, value: "C"),
      TestItem(id: 4, value: "D")
    ]

    let changes = TiledItemChange.make(from: Deque(oldItems), to: newItems)

    #expect(changes.contains(.insert(
      at: 1,
      items: [
        TestItem(id: 2, value: "B"),
        TestItem(id: 3, value: "C")
      ]
    )))
  }
}
