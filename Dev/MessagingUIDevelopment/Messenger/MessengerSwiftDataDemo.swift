//
//  MessengerSwiftDataDemo.swift
//  MessagingUIDevelopment
//
//  Messenger demo with SwiftData persistence.
//

import SwiftUI
import SwiftData
import MessagingUI

// MARK: - SwiftData Model

@Model
final class ChatMessageModel {
  var text: String
  var isSentByMe: Bool
  var timestamp: Date
  var status: MessageStatus

  init(
    text: String,
    isSentByMe: Bool,
    timestamp: Date = .now,
    status: MessageStatus = .sending
  ) {
    self.text = text
    self.isSentByMe = isSentByMe
    self.timestamp = timestamp
    self.status = status
  }
}

// MARK: - ChatMessageItem (Identifiable & Equatable wrapper)

struct ChatMessageItem: Identifiable, Equatable, MessageContentWithStatus {
  let id: PersistentIdentifier
  let text: String
  let isSentByMe: Bool
  let timestamp: Date
  let status: MessageStatus

  init(model: ChatMessageModel) {
    self.id = model.persistentModelID
    self.text = model.text
    self.isSentByMe = model.isSentByMe
    self.timestamp = model.timestamp
    self.status = model.status
  }
}

// MARK: - ChatMessageCell (with context menu)

struct ChatMessageCell: TiledCellContent {
  typealias StateValue = Void

  let item: ChatMessageItem
  var onDelete: (() -> Void)?

  func body(context: CellContext<Void>) -> some View {
    MessageBubbleWithStatusCell(item: item)
      .body(context: context)
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

// MARK: - LoadPosition

enum LoadPosition {
  case end     // Load from newest (default)
  case middle  // Load from middle
}

// MARK: - ChatStore

@Observable
final class ChatStore {

  private let modelContext: ModelContext
  private(set) var dataSource = ListDataSource<ChatMessageItem>()
  var isAutoReceiveEnabled = false

  // Window-based pagination
  private(set) var totalCount = 0
  private var windowStart: Int = 0
  private var windowSize: Int = 0
  private let pageSize = 20
  private var autoReceiveTask: Task<Void, Never>?

  var hasMore: Bool { windowStart > 0 }
  var hasNewer: Bool { windowStart + windowSize < totalCount }

  init(modelContext: ModelContext) {
    self.modelContext = modelContext
  }

  func startAutoReceive() {
    guard autoReceiveTask == nil else { return }
    isAutoReceiveEnabled = true
    autoReceiveTask = Task { @MainActor in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(Double.random(in: 1.5...3.5)))
        guard !Task.isCancelled else { break }
        simulateIncomingMessage()
      }
    }
  }

  func stopAutoReceive() {
    isAutoReceiveEnabled = false
    autoReceiveTask?.cancel()
    autoReceiveTask = nil
  }

  func loadInitial(from position: LoadPosition = .end) {
    totalCount = (try? modelContext.fetchCount(FetchDescriptor<ChatMessageModel>())) ?? 0

    switch position {
    case .end:
      windowStart = max(0, totalCount - pageSize)
      windowSize = min(pageSize, totalCount)
    case .middle:
      windowStart = max(0, totalCount / 2 - pageSize / 2)
      windowSize = min(pageSize, totalCount - windowStart)
    }

    refreshWindow()
  }

  func loadOlder() async {
    guard hasMore else { return }
    try? await Task.sleep(for: .seconds(1))
    let prepend = min(pageSize, windowStart)
    windowStart -= prepend
    windowSize += prepend
    refreshWindow()
  }

  func loadNewer() async {
    guard hasNewer else { return }
    try? await Task.sleep(for: .seconds(1))
    let available = totalCount - (windowStart + windowSize)
    let append = min(pageSize, available)
    windowSize += append
    refreshWindow()
  }

  private func refreshWindow() {
    var descriptor = FetchDescriptor<ChatMessageModel>(
      sortBy: [SortDescriptor(\.timestamp, order: .forward)]
    )
    descriptor.fetchOffset = windowStart
    descriptor.fetchLimit = windowSize

    let models = (try? modelContext.fetch(descriptor)) ?? []
    dataSource.apply(models.map(ChatMessageItem.init))
  }

  func sendMessage(text: String) {
    let message = ChatMessageModel(
      text: text,
      isSentByMe: true,
      status: .sending
    )
    modelContext.insert(message)
    try? modelContext.save()

    // If at the end, extend window to include the new message
    // Check hasNewer before incrementing totalCount to get correct comparison
    if !hasNewer {
      windowSize += 1
    }
    totalCount += 1
    refreshWindow()

    // Simulate sending delay
    let messageID = message.persistentModelID
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(1))
      updateMessageStatus(id: messageID, status: .sent)

      try? await Task.sleep(for: .seconds(0.5))
      updateMessageStatus(id: messageID, status: .delivered)
    }
  }

  func receiveMessage(text: String) {
    let message = ChatMessageModel(
      text: text,
      isSentByMe: false,
      status: .delivered
    )
    modelContext.insert(message)
    try? modelContext.save()

    // If at the end, extend window to include the new message
    // Check hasNewer before incrementing totalCount to get correct comparison
    if !hasNewer {
      windowSize += 1
    }
    totalCount += 1
    refreshWindow()
  }

  private func updateMessageStatus(id: PersistentIdentifier, status: MessageStatus) {
    guard let message = modelContext.model(for: id) as? ChatMessageModel else { return }
    message.status = status
    try? modelContext.save()
    refreshWindow()
  }

  func deleteMessage(id: PersistentIdentifier) {
    guard let message = modelContext.model(for: id) as? ChatMessageModel else { return }
    modelContext.delete(message)
    try? modelContext.save()

    totalCount = max(0, totalCount - 1)
    windowSize = max(0, windowSize - 1)
    refreshWindow()
  }

  // MARK: - Sample Data Generation

  private static let incomingMessages = [
    "Hey! How's it going?",
    "Nice! Any plans for tonight?",
    "Want to grab dinner?",
    "How about that new Italian place?",
    "Cool, I'll make a reservation for 7pm",
    "Can't wait!",
    "Did you see the news today?",
    "That sounds great!",
    "Let me know when you're free",
    "Sure thing!",
    "I was thinking about what you said yesterday, and I think you're absolutely right. We should definitely go ahead with that plan.",
    "Oh by the way, I ran into Sarah at the grocery store today and she was asking about you!",
    "Just finished watching that movie you recommended. Wow, what an incredible story!",
    "Hey, quick question - do you remember the name of that restaurant we went to last month?",
  ]

  private static let outgoingReplies = [
    "Pretty good! Just finished work",
    "Not really, maybe watch a movie",
    "Sure! Where?",
    "Sounds great",
    "Perfect, see you there!",
    "Me neither!",
    "Yeah, crazy stuff",
    "Thanks!",
    "Will do",
    "OK",
  ]

  func simulateIncomingMessage() {
    let text = Self.incomingMessages.randomElement() ?? "Hello!"
    receiveMessage(text: text)
  }

  func generateConversation(count: Int) {
    for i in 0..<count {
      let isSentByMe = Bool.random()
      let text: String
      if isSentByMe {
        text = Self.outgoingReplies.randomElement() ?? "OK"
      } else {
        text = Self.incomingMessages.randomElement() ?? "Hello!"
      }

      let message = ChatMessageModel(
        text: text,
        isSentByMe: isSentByMe,
        timestamp: Date().addingTimeInterval(Double(-count + i) * 60),
        status: .delivered
      )
      modelContext.insert(message)
    }
    try? modelContext.save()

    // Messages are generated with past timestamps, so they appear "before" existing messages
    // Recalculate window to show from the end
    totalCount = (try? modelContext.fetchCount(FetchDescriptor<ChatMessageModel>())) ?? 0
    windowStart = max(0, totalCount - pageSize)
    windowSize = min(pageSize, totalCount)
    refreshWindow()
  }

  func clearAll() {
    try? modelContext.delete(model: ChatMessageModel.self)
    try? modelContext.save()
    totalCount = 0
    windowStart = 0
    windowSize = 0
    dataSource.replace(with: [])
  }
}

// MARK: - MessengerSwiftDataDemo

struct MessengerSwiftDataDemo: View {

  let loadPosition: LoadPosition

  @Environment(\.modelContext) private var modelContext
  @State private var store: ChatStore?
  @State private var inputText = ""
  @State private var scrollPosition: TiledScrollPosition
  @State private var scrollGeometry: TiledScrollGeometry?
  @State private var isTyping = false
  @FocusState private var isInputFocused: Bool

  init(loadPosition: LoadPosition = .end) {
    self.loadPosition = loadPosition
    self._scrollPosition = State(initialValue: TiledScrollPosition(
      autoScrollsToBottomOnAppend: loadPosition == .end,
      scrollsToBottomOnReplace: loadPosition == .end
    ))
  }

  private var isNearBottom: Bool {
    guard let geometry = scrollGeometry else { return true }
    return geometry.pointsFromBottom < 100
  }

  var body: some View {
    ZStack {
      if let store {
        loadedContent(store: store)
      } else {
        ProgressView()
      }
    }
    .navigationTitle("Messages")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Menu {
          Button {
            receiveMessageWithTyping()
          } label: {
            Label("Receive Message", systemImage: "arrow.down.message")
          }
          .disabled(isTyping)

          Button {
            if store?.isAutoReceiveEnabled == true {
              store?.stopAutoReceive()
            } else {
              store?.startAutoReceive()
            }
          } label: {
            if store?.isAutoReceiveEnabled == true {
              Label("Stop Auto Receive", systemImage: "stop.circle")
            } else {
              Label("Start Auto Receive", systemImage: "play.circle")
            }
          }

          Divider()

          Button {
            store?.generateConversation(count: 10)
          } label: {
            Label("Generate 10 Messages", systemImage: "text.bubble")
          }

          Button {
            store?.generateConversation(count: 50)
          } label: {
            Label("Generate 50 Messages", systemImage: "text.bubble.fill")
          }

          Divider()

          Button(role: .destructive) {
            store?.clearAll()
          } label: {
            Label("Clear All", systemImage: "trash")
          }

          Button("Bottom") {
            scrollPosition.scrollTo(edge: .bottom, animated: true)
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
      }
    }
    .onAppear {
      if store == nil {
        store = ChatStore(modelContext: modelContext)
        store?.loadInitial(from: loadPosition)
      }
    }
  }

  @ViewBuilder
  private var inputView: some View {
    let content = HStack(spacing: 12) {
      TextField("Message", text: $inputText)
        .focused($isInputFocused)
        .textFieldStyle(.plain)
        .onSubmit {
          sendMessage()
        }

      Button {
        sendMessage()
      } label: {
        Image(systemName: "arrow.up.circle.fill")
          .font(.title)
          .foregroundStyle(inputText.isEmpty ? .gray : .blue)
      }
      .disabled(inputText.isEmpty)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)

    if #available(iOS 26, *) {
      content
        .glassEffect(.regular.interactive().tint(.clear))
        .padding()
    } else {
      content
        .background(RoundedRectangle(cornerRadius: 20).foregroundStyle(.bar))
        .padding()
    }
  }

  private func loadedContent(store: ChatStore) -> some View {
    ZStack(alignment: .bottomTrailing) {
      TiledView(
        dataSource: store.dataSource,
        scrollPosition: $scrollPosition,
        prependLoader: .loader(perform: {
          await store.loadOlder()
        }) {
          HStack(spacing: 8) {
            ProgressView()
            Text("Loading older messages...")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
        },
        appendLoader: .loader(perform: {
          await store.loadNewer()
        }) {
          HStack(spacing: 8) {
            ProgressView()
            Text("Loading newer messages...")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
        },
        typingIndicator: .indicator(isVisible: isTyping) {
          HStack(spacing: 8) {
            TypingDotsView()
            Text("Someone is typing...")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
        }
      ) { message in
        ChatMessageCell(item: message) {
          store.deleteMessage(id: message.id)
        }
      }
      .revealConfiguration(.default)
      .onDragIntoBottomSafeArea {
        isInputFocused = false
      }
      .onTapBackground {
        isInputFocused = false
      }
      .onTiledScrollGeometryChange { geometry in
        scrollGeometry = geometry
        // Auto-scroll to bottom when near bottom and no newer messages
        if !store.hasNewer {
          scrollPosition.autoScrollsToBottomOnAppend = isNearBottom
        }
      }

      // Scroll to bottom button
      if !isNearBottom {
        Button {
          scrollPosition.scrollTo(edge: .bottom, animated: true)
        } label: {
          Image(systemName: "arrow.down.circle.fill")
            .font(.title)
            .foregroundStyle(.blue)
            .background(Circle().fill(.white))
        }
        .padding()
        .transition(.scale.combined(with: .opacity))
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      inputView
    }
    .animation(.easeInOut(duration: 0.2), value: isNearBottom)
  }

  private func sendMessage() {
    guard !inputText.isEmpty else { return }
    store?.sendMessage(text: inputText)
    inputText = ""
  }

  private func receiveMessageWithTyping() {
    guard !isTyping else { return }

    isTyping = true
    Task {
      // Simulate typing delay
      try? await Task.sleep(for: .seconds(1.5))

      isTyping = false
      store?.simulateIncomingMessage()
    }
  }
}

// MARK: - Preview

#Preview {
  let config = ModelConfiguration(isStoredInMemoryOnly: true)
  let container = try! ModelContainer(for: ChatMessageModel.self, configurations: config)

  let context = container.mainContext
  let conversation: [(String, Bool)] = [
    ("Hey! How's it going?", false),
    ("Pretty good! Just finished work", true),
    ("Nice! Any plans for tonight?", false),
    ("Not really, maybe watch a movie", true),
    ("Want to grab dinner?", false),
    ("Sure! Where?", true),
    ("How about that new Italian place?", false),
    ("Sounds great", true),
    ("Cool, I'll make a reservation for 7pm", false),
    ("Perfect, see you there!", true),
  ]

  for (index, (text, isSentByMe)) in conversation.enumerated() {
    let message = ChatMessageModel(
      text: text,
      isSentByMe: isSentByMe,
      timestamp: Date().addingTimeInterval(Double(index - conversation.count) * 60),
      status: .delivered
    )
    context.insert(message)
  }
  try? context.save()

  return NavigationStack {
    MessengerSwiftDataDemo()
  }
  .modelContainer(container)
}
