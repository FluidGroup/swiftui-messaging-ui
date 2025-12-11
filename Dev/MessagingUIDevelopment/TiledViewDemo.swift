//
//  TiledViewDemo.swift
//  TiledView
//
//  Created by Hiroshi Kimura on 2025/12/10.
//

import SwiftUI
import MessagingUI

// MARK: - Shared Demo Control Panel

struct ListDemoControlPanel: View {

  @Binding var dataSource: ListDataSource<ChatMessage>
  @Binding var nextPrependId: Int
  @Binding var nextAppendId: Int

  var body: some View {
    VStack(spacing: 12) {
      // Row 1: Prepend / Append
      HStack {
        Button("Prepend 5") {
          let messages = generateSampleMessages(count: 5, startId: nextPrependId - 4)
          dataSource.prepend(messages)
          nextPrependId -= 5
        }
        .buttonStyle(.bordered)

        Spacer()

        Button("Append 5") {
          let messages = generateSampleMessages(count: 5, startId: nextAppendId)
          dataSource.append(messages)
          nextAppendId += 5
        }
        .buttonStyle(.bordered)
      }

      // Row 2: Update / Remove
      HStack {
        Button("Update ID:5") {
          if var item = dataSource.items.first(where: { $0.id == 5 }) {
            item.isExpanded.toggle()
            item.text = item.isExpanded ? "UPDATED & EXPANDED!" : "Updated back"
            dataSource.update([item])
          }
        }
        .buttonStyle(.bordered)

        Spacer()

        Button("Remove ID:10") {
          dataSource.remove(id: 10)
        }
        .buttonStyle(.bordered)
      }

      // Row 3: Batch operations (multiple pendingChanges)
      HStack {
        Button("Prepend+Append") {
          // Creates 2 pendingChanges at once
          let prependMessages = generateSampleMessages(count: 3, startId: nextPrependId - 2)
          dataSource.prepend(prependMessages)
          nextPrependId -= 3

          let appendMessages = generateSampleMessages(count: 3, startId: nextAppendId)
          dataSource.append(appendMessages)
          nextAppendId += 3
        }
        .buttonStyle(.bordered)
        .tint(.orange)

        Spacer()

        Button("Append+Prepend") {
          // Creates 2 pendingChanges (append first, then prepend)
          let appendMessages = generateSampleMessages(count: 3, startId: nextAppendId)
          dataSource.append(appendMessages)
          nextAppendId += 3

          let prependMessages = generateSampleMessages(count: 3, startId: nextPrependId - 2)
          dataSource.prepend(prependMessages)
          nextPrependId -= 3
        }
        .buttonStyle(.bordered)
        .tint(.orange)
      }

      // Row 4: SetItems (Reset) + Debug info
      HStack {
        Button("Reset (5 items)") {
          nextPrependId = -1
          nextAppendId = 5
          let newItems = generateSampleMessages(count: 5, startId: 0)
          dataSource.setItems(newItems)
        }
        .buttonStyle(.borderedProminent)

        Spacer()

        VStack(alignment: .trailing, spacing: 2) {
          Text("Count: \(dataSource.items.count)")
            .font(.caption)
          Text("ChangeCounter: \(dataSource.changeCounter)")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

// MARK: - TiledView Demo (UICollectionView)

struct BookTiledView: View {

  @State private var dataSource: ListDataSource<ChatMessage>
  @State private var nextPrependId = -1
  @State private var nextAppendId = 0

  init() {
    _dataSource = State(initialValue: ListDataSource())
  }

  var body: some View {
    VStack(spacing: 0) {
      ListDemoControlPanel(
        dataSource: $dataSource,
        nextPrependId: $nextPrependId,
        nextAppendId: $nextAppendId
      )
      .padding()
      .background(Color(.systemBackground))

      TiledViewRepresentable(
        dataSource: dataSource,
        cellBuilder: { message in
          ChatBubbleView(message: message)
        }
      )
    }
  }
}

// MARK: - MessageList Demo (LazyVStack)

struct BookMessageList: View {

  @State private var dataSource: ListDataSource<ChatMessage>
  @State private var nextPrependId = -1
  @State private var nextAppendId = 0

  init() {
    _dataSource = State(initialValue: ListDataSource())
  }

  var body: some View {
    VStack(spacing: 0) {
      ListDemoControlPanel(
        dataSource: $dataSource,
        nextPrependId: $nextPrependId,
        nextAppendId: $nextAppendId
      )
      .padding()
      .background(Color(.systemBackground))

      MessageList(
        dataSource: dataSource
      ) { message in
        ChatBubbleView(message: message)
      }
    }
  }
}

// MARK: - Comparison Demo (TabView)

struct BookListComparison: View {

  var body: some View {
    TabView {
      BookTiledView()
        .tabItem {
          Label("TiledView", systemImage: "square.grid.2x2")
        }

      BookMessageList()
        .tabItem {
          Label("MessageList", systemImage: "list.bullet")
        }
    }
  }
}

// MARK: - Side-by-Side Comparison (Same DataSource)

struct BookSideBySideComparison: View {

  @State private var dataSource: ListDataSource<ChatMessage>
  @State private var nextPrependId = -1
  @State private var nextAppendId = 0

  init() {
    _dataSource = State(initialValue: ListDataSource())
  }

  var body: some View {
    VStack(spacing: 0) {
      // Shared Control Panel
      ListDemoControlPanel(
        dataSource: $dataSource,
        nextPrependId: $nextPrependId,
        nextAppendId: $nextAppendId
      )
      .padding()
      .background(Color(.systemBackground))

      // Side-by-side views
      HStack(spacing: 1) {
        // Left: TiledView (UICollectionView)
        VStack(spacing: 0) {
          Text("TiledView")
            .font(.caption.bold())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.2))

          TiledViewRepresentable(
            dataSource: dataSource,
            cellBuilder: { message in
              ChatBubbleView(message: message)
            }
          )
        }

        // Right: MessageList (LazyVStack)
        VStack(spacing: 0) {
          Text("MessageList")
            .font(.caption.bold())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.2))

          MessageList(dataSource: dataSource) { message in
            ChatBubbleView(message: message)
          }
        }
      }
      .background(Color(.separator))
    }
  }
}

#Preview("Side by Side") {
  BookSideBySideComparison()
}

#Preview("TiledView (UICollectionView)") {
  BookTiledView()
}

#Preview("MessageList (LazyVStack)") {
  BookMessageList()
}

#Preview("Comparison") {
  BookListComparison()
}
