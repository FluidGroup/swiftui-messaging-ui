//
//  ListDataSourceTests.swift
//  MessagingUITests
//
//  Created by Hiroshi Kimura on 2025/12/12.
//

import Testing
@testable import MessagingUI

struct ListDataSourceTests {

  // MARK: - Test Item

  struct TestItem: Identifiable, Equatable {
    let id: Int
    var value: String
  }

  // MARK: - apply Tests

  @Test
  func emptyToNonEmpty() {
    var dataSource = ListDataSource<TestItem>()
    let newItems = [TestItem(id: 1, value: "A"), TestItem(id: 2, value: "B")]

    dataSource.apply(newItems)

    #expect(Array(dataSource.items) == newItems)
    #expect(dataSource.pendingChanges.last == .replace)
  }

  @Test
  func nonEmptyToEmpty() {
    var dataSource = ListDataSource(items: [TestItem(id: 1, value: "A")])

    dataSource.apply( [])

    #expect(dataSource.items.isEmpty)
    #expect(dataSource.pendingChanges.last == .remove([1]))
  }

  @Test
  func prependItems() {
    var dataSource = ListDataSource(items: [TestItem(id: 2, value: "B")])
    let newItems = [TestItem(id: 1, value: "A"), TestItem(id: 2, value: "B")]

    dataSource.apply( newItems)

    #expect(Array(dataSource.items) == newItems)
    #expect(dataSource.pendingChanges.contains(.prepend([1])))
  }

  @Test
  func appendItems() {
    var dataSource = ListDataSource(items: [TestItem(id: 1, value: "A")])
    let newItems = [TestItem(id: 1, value: "A"), TestItem(id: 2, value: "B")]

    dataSource.apply( newItems)

    #expect(Array(dataSource.items) == newItems)
    #expect(dataSource.pendingChanges.contains(.append([2])))
  }

  @Test
  func insertInMiddle() {
    var dataSource = ListDataSource(items: [
      TestItem(id: 1, value: "A"),
      TestItem(id: 3, value: "C")
    ])
    let newItems = [
      TestItem(id: 1, value: "A"),
      TestItem(id: 2, value: "B"),
      TestItem(id: 3, value: "C")
    ]

    dataSource.apply( newItems)

    #expect(Array(dataSource.items) == newItems)
    #expect(dataSource.pendingChanges.contains(.insert(at: 1, ids: [2])))
  }

  @Test
  func updateItems() {
    var dataSource = ListDataSource(items: [TestItem(id: 1, value: "A")])
    let newItems = [TestItem(id: 1, value: "A-Updated")]

    dataSource.apply( newItems)

    #expect(Array(dataSource.items) == newItems)
    #expect(dataSource.pendingChanges.contains(.update([1])))
  }

  @Test
  func removeItems() {
    var dataSource = ListDataSource(items: [
      TestItem(id: 1, value: "A"),
      TestItem(id: 2, value: "B")
    ])
    let newItems = [TestItem(id: 1, value: "A")]

    dataSource.apply( newItems)

    #expect(Array(dataSource.items) == newItems)
    #expect(dataSource.pendingChanges.contains(.remove([2])))
  }

  @Test
  func complexOperation() {
    // prepend + remove + update
    var dataSource = ListDataSource(items: [
      TestItem(id: 2, value: "B"),
      TestItem(id: 3, value: "C"),
      TestItem(id: 4, value: "D")
    ])
    let newItems = [
      TestItem(id: 1, value: "A"),           // prepend
      TestItem(id: 2, value: "B-Updated"),   // update
      TestItem(id: 3, value: "C")            // unchanged
      // id: 4 removed
    ]

    dataSource.apply( newItems)

    #expect(Array(dataSource.items) == newItems)
    #expect(dataSource.pendingChanges.contains(.remove([4])))
    #expect(dataSource.pendingChanges.contains(.prepend([1])))
    #expect(dataSource.pendingChanges.contains(.update([2])))
  }

  @Test
  func noChanges() {
    let items = [TestItem(id: 1, value: "A"), TestItem(id: 2, value: "B")]
    var dataSource = ListDataSource(items: items)
    let initialChangeCount = dataSource.pendingChanges.count

    dataSource.apply( items)

    // No new changes should be added
    #expect(dataSource.pendingChanges.count == initialChangeCount)
  }

  // MARK: - insert mutation method tests

  @Test
  func insertMutationMethod() {
    var dataSource = ListDataSource(items: [
      TestItem(id: 1, value: "A"),
      TestItem(id: 3, value: "C")
    ])

    dataSource.insert([TestItem(id: 2, value: "B")], at: 1)

    #expect(dataSource.items.count == 3)
    #expect(dataSource.items[1].id == 2)
    #expect(dataSource.pendingChanges.last == .insert(at: 1, ids: [2]))
  }

  @Test
  func insertMultipleItems() {
    var dataSource = ListDataSource(items: [
      TestItem(id: 1, value: "A"),
      TestItem(id: 4, value: "D")
    ])

    dataSource.insert([
      TestItem(id: 2, value: "B"),
      TestItem(id: 3, value: "C")
    ], at: 1)

    #expect(dataSource.items.count == 4)
    #expect(dataSource.items.map { $0.id } == [1, 2, 3, 4])
    #expect(dataSource.pendingChanges.last == .insert(at: 1, ids: [2, 3]))
  }

  @Test
  func insertEmptyArray() {
    var dataSource = ListDataSource(items: [TestItem(id: 1, value: "A")])
    let initialChangeCount = dataSource.pendingChanges.count

    dataSource.insert([], at: 0)

    // No change should be added for empty insert
    #expect(dataSource.pendingChanges.count == initialChangeCount)
  }
}
