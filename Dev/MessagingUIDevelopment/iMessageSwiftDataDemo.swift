//
//  iMessageSwiftDataDemo.swift
//  MessagingUIDevelopment
//
//  Created by Hiroshi Kimura on 2025/12/14.
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

  enum MessageStatus: Int, Codable {
    case sending = 0
    case sent = 1
    case delivered = 2
    case read = 3
    case failed = 4
  }

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

struct ChatMessageItem: Identifiable, Equatable {
  let id: PersistentIdentifier
  let text: String
  let isSentByMe: Bool
  let timestamp: Date
  let status: ChatMessageModel.MessageStatus

  init(model: ChatMessageModel) {
    self.id = model.persistentModelID
    self.text = model.text
    self.isSentByMe = model.isSentByMe
    self.timestamp = model.timestamp
    self.status = model.status
  }
}

// MARK: - iMessage Bubble View

struct iMessageBubbleView: View {

  let message: ChatMessageItem

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    return formatter
  }()

  var body: some View {
    HStack(alignment: .bottom, spacing: 4) {
      if message.isSentByMe {
        Spacer(minLength: 60)
      }

      VStack(alignment: message.isSentByMe ? .trailing : .leading, spacing: 2) {
        Text(message.text)
          .font(.body)
          .foregroundStyle(message.isSentByMe ? .white : .primary)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(
            RoundedRectangle(cornerRadius: 18)
              .fill(bubbleColor)
          )

        HStack(spacing: 4) {
          Text(Self.timeFormatter.string(from: message.timestamp))
            .font(.caption2)
            .foregroundStyle(.secondary)

          if message.isSentByMe {
            statusIcon
          }
        }
      }

      if !message.isSentByMe {
        Spacer(minLength: 60)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 2)
  }

  private var bubbleColor: Color {
    if message.isSentByMe {
      return message.status == .failed ? .red : .blue
    } else {
      return Color(.systemGray5)
    }
  }

  @ViewBuilder
  private var statusIcon: some View {
    switch message.status {
    case .sending:
      ProgressView()
        .scaleEffect(0.5)
        .frame(width: 12, height: 12)
    case .sent:
      Image(systemName: "checkmark")
        .font(.caption2)
        .foregroundStyle(.secondary)
    case .delivered:
      Image(systemName: "checkmark")
        .font(.caption2)
        .foregroundStyle(.blue)
    case .read:
      Image(systemName: "checkmark.circle.fill")
        .font(.caption2)
        .foregroundStyle(.blue)
    case .failed:
      Image(systemName: "exclamationmark.circle.fill")
        .font(.caption2)
        .foregroundStyle(.red)
    }
  }
}

// MARK: - ChatStore

@Observable
final class ChatStore {

  private let modelContext: ModelContext
  private(set) var dataSource = ListDataSource<ChatMessageItem>()
  private(set) var hasMore = true
  var isAutoReceiveEnabled = false

  private var loadedCount = 0
  private let pageSize = 20
  private var autoReceiveTask: Task<Void, Never>?

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

  func loadInitial() {
    loadedCount = pageSize
    refreshFromDatabase()
  }

  func loadMore() {
    guard hasMore else { return }
    loadedCount += pageSize
    refreshFromDatabase()
  }

  private func refreshFromDatabase() {
    let totalCount = (try? modelContext.fetchCount(FetchDescriptor<ChatMessageModel>())) ?? 0
    let offset = max(0, totalCount - loadedCount)

    var descriptor = FetchDescriptor<ChatMessageModel>(
      sortBy: [SortDescriptor(\.timestamp, order: .forward)]
    )
    descriptor.fetchOffset = offset
    descriptor.fetchLimit = loadedCount

    let models = (try? modelContext.fetch(descriptor)) ?? []
    let items = models.map(ChatMessageItem.init)

    dataSource.apply(items)
    hasMore = offset > 0
  }

  func sendMessage(text: String) {
    let message = ChatMessageModel(
      text: text,
      isSentByMe: true,
      status: .sending
    )
    modelContext.insert(message)
    try? modelContext.save()

    loadedCount += 1
    refreshFromDatabase()

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

    loadedCount += 1
    refreshFromDatabase()
  }

  private func updateMessageStatus(id: PersistentIdentifier, status: ChatMessageModel.MessageStatus) {
    guard let message = modelContext.model(for: id) as? ChatMessageModel else { return }
    message.status = status
    try? modelContext.save()
    refreshFromDatabase()
  }

  func deleteMessage(id: PersistentIdentifier) {
    guard let message = modelContext.model(for: id) as? ChatMessageModel else { return }
    modelContext.delete(message)
    try? modelContext.save()

    loadedCount = max(0, loadedCount - 1)
    refreshFromDatabase()
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
    "I was thinking about what you said yesterday, and I think you're absolutely right. We should definitely go ahead with that plan. Let me know what time works best for you and I'll arrange everything.",
    "Oh by the way, I ran into Sarah at the grocery store today and she was asking about you! She said she hasn't seen you in ages and wanted to catch up sometime. Should I give her your number?",
    "Just finished watching that movie you recommended. Wow, what an incredible story! The plot twist at the end completely caught me off guard. Thanks for the suggestion!",
    "Hey, quick question - do you remember the name of that restaurant we went to last month? The one with the amazing pasta? I want to take my parents there this weekend.",
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

    loadedCount += count
    refreshFromDatabase()
  }

  func clearAll() {
    try? modelContext.delete(model: ChatMessageModel.self)
    try? modelContext.save()
    loadedCount = 0
    dataSource.replace(with: [])
    hasMore = false
  }
}

// MARK: - iMessageSwiftDataDemo

struct iMessageSwiftDataDemo: View {

  @Environment(\.modelContext) private var modelContext
  @State private var store: ChatStore?
  @State private var inputText = ""
  @State private var scrollPosition = TiledScrollPosition(
    autoScrollsToBottomOnAppend: true,
    scrollsToBottomOnReplace: true
  )
  @State private var scrollGeometry: TiledScrollGeometry?
  @FocusState private var isInputFocused: Bool

  private var isNearBottom: Bool {
    guard let geometry = scrollGeometry else { return true }
    return geometry.pointsFromBottom < 100
  }

  var body: some View {
    ZStack {
      // Messages
      if let store {
        loadedContent(store: store)
      } else {
        Spacer()
        ProgressView()
        Spacer()
      }
     
    }
    .navigationTitle("Messages")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Menu {
          Button {
            store?.simulateIncomingMessage()
          } label: {
            Label("Receive Message", systemImage: "arrow.down.message")
          }

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
        store?.loadInitial()
      }
    }
  }
  
  @ViewBuilder
  private var inputView: some View {    
    // Input bar
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
        onPrepend: {
          store.loadMore()
        }
      ) { message, _ in
        iMessageBubbleView(message: message)
          .contextMenu {
            Button(role: .destructive) {
              store.deleteMessage(id: message.id)
            } label: {
              Label("Delete", systemImage: "trash")
            }
          }
      }
      .onDragIntoBottomSafeArea {        
        isInputFocused = false
      }
      .onTapBackground {
        isInputFocused = false
      }
      .onTiledScrollGeometryChange { geometry in
        scrollGeometry = geometry
        
        scrollPosition.autoScrollsToBottomOnAppend = isNearBottom
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
    .safeAreaInset(edge: .bottom, spacing: 0, content: {      
      inputView
        .onGeometryChange(for: CGFloat.self) { proxy in
          print(proxy.size)
          return proxy.size.height - proxy.frame(in: .global).minY
        } action: { newValue in
          print("Input view minY: \(newValue)")
        }

    })
    .animation(.easeInOut(duration: 0.2), value: isNearBottom)
  }

  private func sendMessage() {
    guard !inputText.isEmpty else { return }
    store?.sendMessage(text: inputText)
    inputText = ""
  }
}

// MARK: - Preview

#Preview {
  let config = ModelConfiguration(isStoredInMemoryOnly: true)
  let container = try! ModelContainer(for: ChatMessageModel.self, configurations: config)

  // Add sample conversation
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
    iMessageSwiftDataDemo()
  }
  .modelContainer(container)
}
