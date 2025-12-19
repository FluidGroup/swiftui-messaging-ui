//
//  ApplyDiffDemo.swift
//  MessagingUIDevelopment
//
//  Created by Hiroshi Kimura on 2025/12/12.
//

import SwiftUI
import MessagingUI

// MARK: - ApplyDiff Demo

/// Demonstrates the `applyDiff(from:)` method which automatically detects
/// prepend, append, insert, update, and remove operations from array differences.
struct BookApplyDiffDemo: View {

  @State private var dataSource = ListDataSource<ChatMessage>()

  /// Source of truth - the "server" data
  @State private var serverItems: [ChatMessage] = []

  /// Next ID for new items
  @State private var nextId = 0

  /// Log of operations performed
  @State private var operationLog: [String] = []

  /// Previous change counter to detect new changes
  @State private var previousChangeCounter = 0

  @State private var scrollPosition = TiledScrollPosition()

  var body: some View {
    VStack(spacing: 0) {
      // Control Panel
      VStack(spacing: 12) {
        Text("applyDiff Demo")
          .font(.headline)

        Text("Modify the 'server' array, then applyDiff auto-detects changes")
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)

        // Row 1: Basic operations
        HStack {
          Button("Prepend") {
            let newItem = ChatMessage(id: nextId, text: "Prepended #\(nextId)")
            nextId += 1
            serverItems.insert(newItem, at: 0)
            applyAndLog("prepend(1)")
          }
          .buttonStyle(.bordered)

          Button("Append") {
            let newItem = ChatMessage(id: nextId, text: "Appended #\(nextId)")
            nextId += 1
            serverItems.append(newItem)
            applyAndLog("append(1)")
          }
          .buttonStyle(.bordered)

          Button("Insert Mid") {
            guard serverItems.count >= 2 else {
              serverItems.append(ChatMessage(id: nextId, text: "First #\(nextId)"))
              nextId += 1
              applyAndLog("setItems")
              return
            }
            let midIndex = serverItems.count / 2
            let newItem = ChatMessage(id: nextId, text: "Inserted #\(nextId)")
            nextId += 1
            serverItems.insert(newItem, at: midIndex)
            applyAndLog("insert@\(midIndex)(1)")
          }
          .buttonStyle(.bordered)
        }

        // Row 2: Update / Remove
        HStack {
          Button("Update First") {
            guard !serverItems.isEmpty else { return }
            serverItems[0].text = "Updated! \(Date().formatted(date: .omitted, time: .standard))"
            applyAndLog("update(1)")
          }
          .buttonStyle(.bordered)

          Button("Remove Last") {
            guard !serverItems.isEmpty else { return }
            serverItems.removeLast()
            applyAndLog("remove(1)")
          }
          .buttonStyle(.bordered)

          Button("Shuffle") {
            serverItems.shuffle()
            applyAndLog("shuffle→setItems")
          }
          .buttonStyle(.bordered)
        }

        // Row 3: Complex operations
        HStack {
          Button("Prepend+Update+Remove") {
            guard serverItems.count >= 2 else {
              // Initialize with some items
              serverItems = [
                ChatMessage(id: nextId, text: "Item A"),
                ChatMessage(id: nextId + 1, text: "Item B"),
                ChatMessage(id: nextId + 2, text: "Item C"),
              ]
              nextId += 3
              applyAndLog("setItems(3)")
              return
            }

            // Prepend new item
            let newItem = ChatMessage(id: nextId, text: "New Prepended #\(nextId)")
            nextId += 1
            serverItems.insert(newItem, at: 0)

            // Update second item (was first before prepend)
            if serverItems.count > 1 {
              serverItems[1].text = "Updated!"
            }

            // Remove last item
            serverItems.removeLast()

            applyAndLog("remove+prepend+update")
          }
          .buttonStyle(.bordered)
          .tint(.orange)

          Button("Reset") {
            serverItems = []
            nextId = 0
            operationLog = []
            previousChangeCounter = 0
            dataSource = ListDataSource()
          }
          .buttonStyle(.borderedProminent)
          .tint(.red)
        }

        // Stats
        HStack {
          Text("Items: \(serverItems.count)")
          Spacer()
          Text("ChangeCounter: \(dataSource.changeCounter)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      .padding()
      .background(Color(.systemBackground))

      Divider()

      // Operation Log
      VStack(alignment: .leading, spacing: 4) {
        Text("Operation Log (expected changes):")
          .font(.caption.bold())
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(operationLog.suffix(10), id: \.self) { log in
              Text(log)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(logColor(for: log).opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
          }
        }
      }
      .padding(.horizontal)
      .padding(.vertical, 8)
      .background(Color(.secondarySystemBackground))

      Divider()

      // List View
      TiledView(
        dataSource: dataSource,
        scrollPosition: $scrollPosition,
        cellBuilder: { message, _ in
          ChatBubbleCell(item: message)
        }
      )
    }
  }

  private func applyAndLog(_ expectedChange: String) {
    var updatedDataSource = dataSource
    updatedDataSource.apply(serverItems)

    // Check if change counter increased
    let newCounter = updatedDataSource.changeCounter
    if newCounter > previousChangeCounter {
      operationLog.append(expectedChange)
      previousChangeCounter = newCounter
    }

    dataSource = updatedDataSource
  }

  private func logColor(for log: String) -> Color {
    if log.contains("prepend") { return .blue }
    if log.contains("append") { return .green }
    if log.contains("insert") { return .purple }
    if log.contains("update") { return .orange }
    if log.contains("remove") { return .red }
    if log.contains("setItems") || log.contains("shuffle") { return .gray }
    return .primary
  }
}

#Preview("ApplyDiff Demo") {
  BookApplyDiffDemo()
}
