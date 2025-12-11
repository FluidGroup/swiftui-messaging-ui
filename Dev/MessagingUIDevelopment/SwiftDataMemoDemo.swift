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
  }
}

// MARK: - MemoStore

@Observable
final class MemoStore {

  private let modelContext: ModelContext
  private(set) var dataSource = ListDataSource<MemoItem>()
  private(set) var hasMore = true
  private var oldestLoadedDate: Date?

  private let pageSize = 10

  init(modelContext: ModelContext) {
    self.modelContext = modelContext
  }

  func loadInitial() {
    var descriptor = FetchDescriptor<Memo>(
      sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
    )
    descriptor.fetchLimit = pageSize

    let memos = (try? modelContext.fetch(descriptor)) ?? []
    // 表示は古い→新しいなので reverse
    let items = memos.reversed().map(MemoItem.init)
    dataSource.setItems(Array(items))
    oldestLoadedDate = memos.last?.createdAt
    hasMore = memos.count == pageSize
  }

  func loadMore() {
    guard let oldestDate = oldestLoadedDate, hasMore else { return }

    var descriptor = FetchDescriptor<Memo>(
      predicate: #Predicate { $0.createdAt < oldestDate },
      sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
    )
    descriptor.fetchLimit = pageSize

    let memos = (try? modelContext.fetch(descriptor)) ?? []
    // prependなので古い順に追加
    let items = memos.reversed().map(MemoItem.init)
    dataSource.prepend(Array(items))
    oldestLoadedDate = memos.last?.createdAt
    hasMore = memos.count == pageSize
  }

  func addMemo(text: String) {
    let memo = Memo(text: text)
    modelContext.insert(memo)
    try? modelContext.save()
    dataSource.append([MemoItem(memo: memo)])
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
      dataSource.append([MemoItem(memo: memo)])
    }
    try? modelContext.save()
  }
}

// MARK: - SwiftDataMemoDemo

struct SwiftDataMemoDemo: View {

  @Environment(\.modelContext) private var modelContext
  @State private var store: MemoStore?
  @State private var inputText = ""

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
        VStack(spacing: 0) {
          // Load More button
          if store.hasMore {
            Button("Load More") {
              store.loadMore()
            }
            .buttonStyle(.bordered)
            .padding(.vertical, 8)
          }

          TiledView(
            dataSource: store.dataSource,
            cellBuilder: { item in
              MemoBubbleView(item: item)
            }
          )
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
