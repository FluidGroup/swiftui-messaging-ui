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
  @State private var scrollPosition = TiledScrollPosition()

  // TiledView options
  @State private var cachesCellState = false

  let namespace: Namespace.ID

  init(namespace: Namespace.ID) {
    self.namespace = namespace
    _dataSource = State(initialValue: ListDataSource())
  }

  var body: some View {
    Group {
      if #available(iOS 18.0, *) {
        TiledView(
          dataSource: dataSource,
          scrollPosition: $scrollPosition,
          cachesCellState: cachesCellState,
          cellBuilder: { message in
            NavigationLink(value: message) {
              StatefulChatBubbleView(message: message, namespace: namespace)
            }
          }
        )
      } else {
        TiledView(
          dataSource: dataSource,
          scrollPosition: $scrollPosition,
          cachesCellState: cachesCellState,
          cellBuilder: { message in
            StatefulChatBubbleView(message: message, namespace: nil)
          }
        )
      }
    }
    .safeAreaInset(edge: .bottom) {
      VStack(spacing: 0) {
        Divider()
        HStack {
          Text("\(dataSource.items.count) items")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          HStack(spacing: 12) {
            Toggle("Cache State", isOn: $cachesCellState)
              .font(.caption)
              .toggleStyle(.switch)
              .controlSize(.mini)
            Text("v\(dataSource.changeCounter)")
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
      }
      .background(.bar)
    }
    .toolbar {
      ToolbarItemGroup(placement: .bottomBar) {
        // Prepend
        Button {
          let messages = generateSampleMessages(count: 5, startId: nextPrependId - 4)
          dataSource.prepend(messages)
          nextPrependId -= 5
        } label: {
          Image(systemName: "arrow.up.doc")
        }

        // Append
        Button {
          let messages = generateSampleMessages(count: 5, startId: nextAppendId)
          dataSource.append(messages)
          nextAppendId += 5
        } label: {
          Image(systemName: "arrow.down.doc")
        }

        // Insert at middle
        Button {
          let middleIndex = dataSource.items.count / 2
          let message = ChatMessage(id: nextAppendId, text: "Inserted at \(middleIndex)")
          dataSource.insert([message], at: middleIndex)
          nextAppendId += 1
        } label: {
          Image(systemName: "arrow.right.doc.on.clipboard")
        }

        Spacer()

        // Update
        Button {
          if var item = dataSource.items.first(where: { $0.id == 5 }) {
            item.isExpanded.toggle()
            item.text = item.isExpanded ? "UPDATED & EXPANDED!" : "Updated back"
            dataSource.update([item])
          }
        } label: {
          Image(systemName: "pencil")
        }

        // Remove
        Button {
          dataSource.remove(id: 10)
        } label: {
          Image(systemName: "trash")
        }

        Spacer()

        // Scroll to Top
        Button {
          scrollPosition.scrollTo(edge: .top)
        } label: {
          Image(systemName: "arrow.up.to.line")
        }

        // Scroll to Bottom
        Button {
          scrollPosition.scrollTo(edge: .bottom)
        } label: {
          Image(systemName: "arrow.down.to.line")
        }

        Spacer()

        // Reset
        Button {
          nextPrependId = -1
          nextAppendId = 5
          let newItems = generateSampleMessages(count: 5, startId: 0)
          dataSource.setItems(newItems)
        } label: {
          Image(systemName: "arrow.counterclockwise")
        }
      }
    }
  }
}

// MARK: - StatefulChatBubbleView

/// A chat bubble view with internal @State to demonstrate state persistence.
/// When cachesCellState is enabled, the tap count persists across cell reuse.
struct StatefulChatBubbleView: View {

  let message: ChatMessage
  let namespace: Namespace.ID?

  @State private var tapCount = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      chatBubbleContent
      Text("Taps: \(tapCount)")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .contentShape(Rectangle())
    .onTapGesture {
      tapCount += 1
    }
  }

  @ViewBuilder
  private var chatBubbleContent: some View {
    if #available(iOS 18.0, *), let namespace {
      ChatBubbleView(message: message)
        .matchedTransitionSource(id: message.id, in: namespace)
    } else {
      ChatBubbleView(message: message)
    }
  }
}

#Preview("TiledView (UICollectionView)") {
  struct PreviewWrapper: View {
    @Namespace private var namespace

    var body: some View {
      NavigationStack {
        BookTiledView(namespace: namespace)
          .navigationDestination(for: ChatMessage.self) { message in
            if #available(iOS 18.0, *) {
              Text("Detail View for Message ID: \(message.id)")
                .navigationTransition(
                  .zoom(sourceID: message.id, in: namespace)
                )
            } else {
              Text("Detail View for Message ID: \(message.id)")
            }
          }
      }
    }
  }
  return PreviewWrapper()
}
