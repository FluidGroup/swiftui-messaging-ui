//
//  SwiftDataMemoDemo.swift
//  MessagingUIDevelopment
//
//  Created by Claude on 2025/12/12.
//

import SwiftUI
import SwiftData
import MessagingUI

// MARK: - SwiftData Model

@Model
final class Memo {
  var text: String
  var createdAt: Date

  init(text: String, createdAt: Date = .now) {
    self.text = text
    self.createdAt = createdAt
  }
}

// MARK: - MemoItem (Identifiable & Equatable wrapper)

struct MemoItem: Identifiable, Equatable {
  let id: PersistentIdentifier
  let text: String
  let createdAt: Date

  init(memo: Memo) {
    self.id = memo.persistentModelID
    self.text = memo.text
    self.createdAt = memo.createdAt
  }
}

// MARK: - MemoBubbleView

struct MemoBubbleView: View {

  let item: MemoItem
  var onDelete: (() -> Void)?

  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter
  }()

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text(item.text)
          .font(.system(size: 16))
          .fixedSize(horizontal: false, vertical: true)

        Text(Self.dateFormatter.string(from: item.createdAt))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(12)
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(Color(.systemGray6))
      )

      Spacer(minLength: 44)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 4)
    .contextMenu {
      if let onDelete {
        Button(role: .destructive) {
          onDelete()
        } label: {
          Label("Delete", systemImage: "trash")
        }
      }
    }
  }
}

// MARK: - MemoBubbleCell (TiledCellContent)

struct MemoBubbleCell: TiledCellContent {

  let item: MemoItem
  var onDelete: (() -> Void)?

  func body(context: CellContext) -> some View {
    MemoBubbleView(item: item, onDelete: onDelete)
  }
}

// MARK: - MemoStore (using applyDiff)

@Observable
final class MemoStore {

  private let modelContext: ModelContext
  private(set) var dataSource = ListDataSource<MemoItem>()
  private(set) var hasMore = true

  /// Current loaded item count for pagination
  private var loadedCount = 0
  private let pageSize = 10

  init(modelContext: ModelContext) {
    self.modelContext = modelContext
  }

  /// Initial load: fetch latest 10 items
  func loadInitial() {
    loadedCount = pageSize
    refreshFromDatabase()
  }

  /// Load older memos: increase fetch count and re-fetch
  func loadMore() {
    guard hasMore else { return }
    loadedCount += pageSize
    refreshFromDatabase()
  }

  /// Fetch from SwiftData and apply diff
  private func refreshFromDatabase() {
    // Get total count to calculate offset
    let totalCount = (try? modelContext.fetchCount(FetchDescriptor<Memo>())) ?? 0
    let offset = max(0, totalCount - loadedCount)

    var descriptor = FetchDescriptor<Memo>(
      sortBy: [SortDescriptor(\.createdAt, order: .forward)]  // oldest to newest
    )
    descriptor.fetchOffset = offset
    descriptor.fetchLimit = loadedCount

    let memos = (try? modelContext.fetch(descriptor)) ?? []
    let items = memos.map(MemoItem.init)

    // Automatically detect and apply diff
    dataSource.apply(items)

    hasMore = offset > 0
  }

  /// Add new memo and refresh
  func addMemo(text: String) {
    let memo = Memo(text: text)
    modelContext.insert(memo)
    try? modelContext.save()

    // Increment count and refresh after adding
    loadedCount += 1
    refreshFromDatabase()
  }

  /// Delete memo by ID and refresh
  func deleteMemo(id: PersistentIdentifier) {
    guard let memo = modelContext.model(for: id) as? Memo else { return }
    modelContext.delete(memo)
    try? modelContext.save()

    // Decrement count and refresh after deleting
    loadedCount = max(0, loadedCount - 1)
    refreshFromDatabase()
  }

  private static let sampleTexts = [
    "Hello!",
    "How are you today?",
    "I'm working on a new project.",
    "SwiftData is really convenient.",
    "TiledView works great for chat UIs!",
    "This is a longer message to test how the layout handles multi-line content.",
    "Short one.",
    "Another memo here.",
    "Testing pagination...",
    "Quick note 📝",
  ]

  func addRandomMemo() {
    let text = Self.sampleTexts.randomElement() ?? "New memo"
    addMemo(text: text)
  }

  func addMultipleMemos(count: Int) {
    for _ in 0..<count {
      let text = Self.sampleTexts.randomElement() ?? "New memo"
      let memo = Memo(text: text)
      modelContext.insert(memo)
    }
    try? modelContext.save()

    // Increment count by added amount and refresh
    loadedCount += count
    refreshFromDatabase()
  }
}

// MARK: - SwiftDataMemoDemo

struct SwiftDataMemoDemo: View {

  @Environment(\.modelContext) private var modelContext
  @State private var store: MemoStore?
  @State private var inputText = ""
  @State private var scrollPosition = TiledScrollPosition()

  var body: some View {
    VStack(spacing: 0) {
      // Input area
      VStack(spacing: 8) {
        HStack {
          TextField("New memo...", text: $inputText)
            .textFieldStyle(.roundedBorder)

          Button {
            guard !inputText.isEmpty else { return }
            store?.addMemo(text: inputText)
            inputText = ""
          } label: {
            Image(systemName: "paperplane.fill")
          }
          .buttonStyle(.borderedProminent)
          .disabled(inputText.isEmpty)
        }

        // Quick add buttons
        HStack {
          Button("+ Random") {
            store?.addRandomMemo()
          }
          .buttonStyle(.bordered)

          Button("+ 5 Items") {
            store?.addMultipleMemos(count: 5)
          }
          .buttonStyle(.bordered)

          Button("+ 10 Items") {
            store?.addMultipleMemos(count: 10)
          }
          .buttonStyle(.bordered)
        }
        .font(.caption)
      }
      .padding()
      .background(Color(.systemBackground))

      Divider()

      // Memo list
      if let store {
        TiledView(
          dataSource: store.dataSource,
          scrollPosition: $scrollPosition,
          prependLoader: .loader(perform: {
            store.loadMore()
          }, isProcessing: false) {
            EmptyView()
          }
        ) { item, _ in
          MemoBubbleCell(item: item) {
            store.deleteMemo(id: item.id)
          }
        }
      } else {
        Spacer()
        ProgressView()
        Spacer()
      }
    }
    .navigationTitle("Memo Stream")
    .onAppear {
      if store == nil {
        store = MemoStore(modelContext: modelContext)
        store?.loadInitial()
      }
    }
  }
}

// MARK: - Preview

#Preview {
  let config = ModelConfiguration(isStoredInMemoryOnly: true)
  let container = try! ModelContainer(for: Memo.self, configurations: config)

  // Add sample data
  let context = container.mainContext
  let sampleTexts = [
    "Hello!",
    "How are you today?",
    "I'm working on a new project.",
    "SwiftData is really convenient.",
    "TiledView works great for chat UIs!",
    "This is a longer message to test how the layout handles multi-line content. It should wrap nicely.",
    "Short one.",
    "Another memo here.",
    "Testing pagination...",
    "10th memo",
    "11th memo",
    "12th memo",
    "13th memo",
    "14th memo",
    "15th memo",
  ]

  for (index, text) in sampleTexts.enumerated() {
    let memo = Memo(
      text: text,
      createdAt: Date().addingTimeInterval(TimeInterval(-index * 60))
    )
    context.insert(memo)
  }
  try? context.save()

  return NavigationStack {
    SwiftDataMemoDemo()
  }
  .modelContainer(container)
}
