//
//  ApplyDiffDemo.swift
//  MessagingUIDevelopment
//
//  Created by Hiroshi Kimura on 2025/12/12.
//

import SwiftUI
import MessagingUI

// MARK: - ApplyDiff Demo

/// Demonstrates the item snapshot API, which internally detects
/// prepend, append, insert, update, and remove operations from array differences.
struct BookApplyDiffDemo: View {

  @State private var items: [ChatMessage] = []

  /// Source of truth - the "server" data
  @State private var serverItems: [ChatMessage] = []

  /// Next ID for new items
  @State private var nextId = 0

  /// Log of operations performed
  @State private var operationLog: [String] = []

  @State private var scrollPosition = TiledScrollPosition()

  var body: some View {
    VStack(spacing: 0) {
      // Control Panel
      VStack(spacing: 12) {
        Text("applyDiff Demo")
          .font(.headline)

        Text("Modify the 'server' array, then TiledView auto-detects changes from [Item]")
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
            items = []
            nextId = 0
            operationLog = []
          }
          .buttonStyle(.borderedProminent)
          .tint(.red)
        }

        // Stats
        HStack {
          Text("Items: \(serverItems.count)")
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
        items: items,
        scrollPosition: $scrollPosition,
        makeInitialState: { _ in ChatBubbleCellState() }
      ) { message in
        ChatBubbleCell(item: message)
      }
    }
  }

  private func applyAndLog(_ expectedChange: String) {
    items = serverItems
    operationLog.append(expectedChange)
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

// MARK: - Batch Update Repro Demo

/// Stresses TiledView with multiple item snapshot changes.
///
/// This intentionally creates rapid same-render item changes so TiledUIView
/// recomputes diffs from the displayed items to the latest snapshot.
struct BatchUpdateReproDemo: View {

  @State private var items = generateSampleMessages(count: 24, startId: 0)
  @State private var scrollPosition = TiledScrollPosition()
  @State private var nextAppendId = 24
  @State private var nextPrependId = -1
  @State private var runCount = 0
  @State private var isStressRunning = false

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 12) {
        Text("Batch Update Repro")
          .font(.headline)

        Text("Tap buttons below to apply multiple item changes before TiledView receives the next SwiftUI update.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)

        HStack {
          Button("Append x2") {
            appendBurst(changeCount: 2)
          }
          .buttonStyle(.bordered)

          Button("Append x5") {
            appendBurst(changeCount: 5)
          }
          .buttonStyle(.bordered)
          .tint(.orange)

          Button("Mixed") {
            mixedBurst()
          }
          .buttonStyle(.bordered)
          .tint(.purple)
        }

        HStack {
          Button(isStressRunning ? "Running..." : "Stress 100") {
            runStress()
          }
          .buttonStyle(.borderedProminent)
          .disabled(isStressRunning)

          Button("Reset") {
            reset()
          }
          .buttonStyle(.bordered)
          .tint(.red)
        }

        HStack {
          Text("Items: \(items.count)")
          Spacer()
          Text("Runs: \(runCount)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      .padding()
      .background(Color(.systemBackground))

      Divider()

      TiledView(
        items: items,
        scrollPosition: $scrollPosition,
        makeInitialState: { _ in ChatBubbleCellState() }
      ) { message in
        ChatBubbleCell(item: message)
      }
    }
  }

  private func appendBurst(changeCount: Int) {
    var nextItems = items

    for _ in 0..<changeCount {
      let message = ChatMessage(
        id: nextAppendId,
        text: "Same-render append #\(nextAppendId)"
      )
      nextAppendId += 1
      nextItems.append(message)
    }

    items = nextItems
    runCount += 1
  }

  private func mixedBurst() {
    var nextItems = items

    let prependedMessage = ChatMessage(
      id: nextPrependId,
      text: "Same-render prepend #\(nextPrependId)"
    )
    nextPrependId -= 1
    nextItems.insert(prependedMessage, at: 0)

    let appendedMessage = ChatMessage(
      id: nextAppendId,
      text: "Same-render append #\(nextAppendId)"
    )
    nextAppendId += 1
    nextItems.append(appendedMessage)

    if let removableID = nextItems.dropFirst().first?.id {
      nextItems.remove(id: removableID)
    }

    items = nextItems
    runCount += 1
  }

  private func runStress() {
    guard !isStressRunning else { return }

    isStressRunning = true

    Task { @MainActor in
      for _ in 0..<100 {
        appendBurst(changeCount: 2)
        try? await Task.sleep(for: .milliseconds(20))
      }

      isStressRunning = false
    }
  }

  private func reset() {
    items = generateSampleMessages(count: 24, startId: 0)
    scrollPosition = TiledScrollPosition()
    nextAppendId = 24
    nextPrependId = -1
    runCount = 0
    isStressRunning = false
  }
}

#Preview("Batch Update Repro") {
  BatchUpdateReproDemo()
}
