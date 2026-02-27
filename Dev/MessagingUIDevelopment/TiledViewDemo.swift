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
            item.text = "UPDATED! \(Date().formatted(date: .omitted, time: .standard))"
            dataSource.updateExisting([item])
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
          dataSource.replace(with:newItems)
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

  @State private var dataSource = ListDataSource<ChatMessage>()
  @State private var nextPrependId = -1
  @State private var nextAppendId = 0
  @State private var scrollPosition = TiledScrollPosition()

  let namespace: Namespace.ID
  
  var body: some View {
    ZStack {
      TiledView(
        dataSource: dataSource,
        scrollPosition: $scrollPosition,
        makeInitialState: { _ in ChatBubbleCellState() }
      ) { message in
        ChatBubbleCellWithNavigation(item: message, namespace: namespace, useMatchedTransition: true)
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(spacing: 0) {
        Divider()
        HStack {
          Text("\(dataSource.items.count) items")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          HStack(spacing: 12) {
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

        Spacer()

        // Scroll
        Button {
          scrollPosition.scrollTo(edge: .top)
        } label: {
          Image(systemName: "arrow.up.to.line")
        }

        Button {
          scrollPosition.scrollTo(edge: .bottom)
        } label: {
          Image(systemName: "arrow.down.to.line")
        }

        Spacer()

        // More actions
        Menu {
          Button {
            let middleIndex = dataSource.items.count / 2
            let message = ChatMessage(id: nextAppendId, text: "Inserted at \(middleIndex)")
            dataSource.insert([message], at: middleIndex)
            nextAppendId += 1
          } label: {
            Label("Insert at middle", systemImage: "arrow.right.doc.on.clipboard")
          }

          Button {
            if var item = dataSource.items.first(where: { $0.id == 5 }) {
              item.text = "UPDATED! \(Date().formatted(date: .omitted, time: .standard))"
              dataSource.updateExisting([item])
            }
          } label: {
            Label("Update ID:5", systemImage: "pencil")
          }

          Button(role: .destructive) {
            dataSource.remove(id: 10)
          } label: {
            Label("Remove ID:10", systemImage: "trash")
          }

          Divider()

          Button {
            nextPrependId = -1
            nextAppendId = 5
            let newItems = generateSampleMessages(count: 5, startId: 0)
            dataSource.replace(with:newItems)
          } label: {
            Label("Reset", systemImage: "arrow.counterclockwise")
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
      }
    }
    .navigationTitle("TiledView")
    .navigationBarTitleDisplayMode(.inline)
  }
}

// MARK: - Loading Indicator Demo

struct BookTiledViewLoadingIndicator: View {

  @State private var dataSource = ListDataSource<ChatMessage>()
  @State private var nextPrependId = -1
  @State private var nextAppendId = 0
  @State private var scrollPosition = TiledScrollPosition()
  @State private var isPrependLoading = false
  @State private var isAppendLoading = false

  var body: some View {
    TiledView(
      dataSource: dataSource,
      scrollPosition: $scrollPosition,
      makeInitialState: { _ in ChatBubbleCellState() }
    ) { message in
      ChatBubbleCell(item: message)
    }
    .prependLoader(.loader(
      perform: { /* triggered by button */ },
      isProcessing: isPrependLoading
    ) {
      HStack {
        ProgressView()
        Text("Loading older messages...")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)
      .padding()
    })
    .appendLoader(.loader(
      perform: { /* triggered by button */ },
      isProcessing: isAppendLoading
    ) {
      HStack {
        ProgressView()
        Text("Loading newer messages...")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)
      .padding()
    })
    .safeAreaInset(edge: .bottom) {
      VStack(spacing: 0) {
        Divider()
        HStack {
          Text("\(dataSource.items.count) items")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          HStack(spacing: 8) {
            if isPrependLoading {
              Text("Prepend...")
                .font(.caption2)
                .foregroundStyle(.orange)
            }
            if isAppendLoading {
              Text("Append...")
                .font(.caption2)
                .foregroundStyle(.orange)
            }
          }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
      }
      .background(.bar)
    }
    .toolbar {
      ToolbarItemGroup(placement: .bottomBar) {
        // Toggle Prepend Loading
        Button {
          isPrependLoading.toggle()
          if isPrependLoading {
            // Simulate loading and prepend after 2 seconds
            Task {
              try? await Task.sleep(for: .seconds(2))
              let messages = generateSampleMessages(count: 5, startId: nextPrependId - 4)
              dataSource.prepend(messages)
              nextPrependId -= 5
              isPrependLoading = false
            }
          }
        } label: {
          Label("Load Older", systemImage: isPrependLoading ? "hourglass" : "arrow.up.doc")
        }

        // Toggle Append Loading
        Button {
          isAppendLoading.toggle()
          if isAppendLoading {
            // Simulate loading and append after 2 seconds
            Task {
              try? await Task.sleep(for: .seconds(2))
              let messages = generateSampleMessages(count: 5, startId: nextAppendId)
              dataSource.append(messages)
              nextAppendId += 5
              isAppendLoading = false
            }
          }
        } label: {
          Label("Load Newer", systemImage: isAppendLoading ? "hourglass" : "arrow.down.doc")
        }

        Spacer()

        // Scroll
        Button {
          scrollPosition.scrollTo(edge: .top)
        } label: {
          Image(systemName: "arrow.up.to.line")
        }

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
          isPrependLoading = false
          isAppendLoading = false
          let newItems = generateSampleMessages(count: 5, startId: 0)
          dataSource.replace(with: newItems)
        } label: {
          Image(systemName: "arrow.counterclockwise")
        }
      }
    }
    .navigationTitle("Loading Indicators")
  }
}

#Preview("TiledView (UICollectionView)") {
  @Previewable @Namespace var namespace
  NavigationStack {
    BookTiledView(namespace: namespace)
      .navigationDestination(for: ChatMessage.self) { message in
        if #available(iOS 18.0, *) {
          Text("Detail View for Message ID: \(message.id)")
            .navigationTransition(.zoom(sourceID: message.id, in: namespace))
        } else {
          Text("Detail View for Message ID: \(message.id)")
        }
      }
  }
}

// MARK: - Typing Indicator Demo

struct BookTiledViewTypingIndicator: View {

  @State private var dataSource = ListDataSource<ChatMessage>()
  @State private var nextPrependId = -1
  @State private var nextAppendId = 0
  @State private var scrollPosition = TiledScrollPosition()
  @State private var isTyping = false
  @State private var isAppendLoading = false

  var body: some View {
    TiledView(
      dataSource: dataSource,
      scrollPosition: $scrollPosition,
      makeInitialState: { _ in ChatBubbleCellState() }
    ) { message in
      ChatBubbleCell(item: message)
    }
    .appendLoader(.loader(
      perform: { /* triggered by button */ },
      isProcessing: isAppendLoading
    ) {
      HStack {
        ProgressView()
        Text("Loading newer messages...")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)
      .padding()
    })
    .typingIndicator(.indicator(isVisible: isTyping) {
      HStack(spacing: 8) {
        TypingDotsView()
        Text("Someone is typing...")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(Color(.systemGray6))
    })
    .safeAreaInset(edge: .bottom) {
      VStack(spacing: 0) {
        Divider()
        HStack {
          Text("\(dataSource.items.count) items")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()
          if isTyping {
            Text("Typing...")
              .font(.caption2)
              .foregroundStyle(.blue)
          }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
      }
      .background(.bar)
    }
    .toolbar {
      ToolbarItemGroup(placement: .bottomBar) {
        // Toggle Typing Indicator
        Button {
          withAnimation {
            isTyping.toggle()
          }
        } label: {
          Label(
            isTyping ? "Hide Typing" : "Show Typing",
            systemImage: isTyping ? "ellipsis.bubble.fill" : "ellipsis.bubble"
          )
        }
        .tint(isTyping ? .blue : nil)

        // Toggle Append Loading
        Button {
          isAppendLoading.toggle()
          if isAppendLoading {
            Task {
              try? await Task.sleep(for: .seconds(2))
              let messages = generateSampleMessages(count: 5, startId: nextAppendId)
              dataSource.append(messages)
              nextAppendId += 5
              isAppendLoading = false
            }
          }
        } label: {
          Label("Load Newer", systemImage: isAppendLoading ? "hourglass" : "arrow.down.doc")
        }

        Spacer()

        // Append
        Button {
          let messages = generateSampleMessages(count: 5, startId: nextAppendId)
          dataSource.append(messages)
          nextAppendId += 5
        } label: {
          Image(systemName: "arrow.down.doc")
        }

        // Scroll
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
          isTyping = false
          isAppendLoading = false
          let newItems = generateSampleMessages(count: 5, startId: 0)
          dataSource.replace(with: newItems)
        } label: {
          Image(systemName: "arrow.counterclockwise")
        }
      }
    }
    .navigationTitle("Typing Indicator")
  }
}

// Animated typing dots
struct TypingDotsView: View {
  @State private var isAnimating = false

  var body: some View {
    HStack(spacing: 5) {
      ForEach(0..<3) { index in
        Circle()
          .fill(
            LinearGradient(
              colors: [Color.gray.opacity(0.6), Color.gray.opacity(0.4)],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .frame(width: 10, height: 10)
          .scaleEffect(isAnimating ? 1.0 : 0.6)
          .offset(y: isAnimating ? -6 : 2)
          .animation(
            .easeInOut(duration: 0.5)
              .repeatForever(autoreverses: true)
              .delay(Double(index) * 0.15),
            value: isAnimating
          )
      }
    }
    .onAppear {
      isAnimating = true
    }
  }
}

// MARK: - Expandable Header View

struct ExpandableConversationHeader: View {

  @State private var isExpanded = false
  @Environment(\.updateSelfSizing) private var updateSelfSizing

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: "lock.shield")
        .font(.title)
        .foregroundStyle(.secondary)
      Text("Start of conversation")
        .font(.subheadline)
        .fontWeight(.semibold)
      Text("Messages in this chat are not end-to-end encrypted.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      if isExpanded {
        VStack(spacing: 6) {
          Text("Channel created on January 1, 2025")
          Text("Members: Alice, Bob, Charlie, Dave")
          Text("This is a private channel visible only to invited members.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .transition(.opacity)
      }

      Button {
        isExpanded.toggle()
        updateSelfSizing()
      } label: {
        HStack(spacing: 4) {
          Text(isExpanded ? "Show Less" : "Show More")
          Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
        }
        .font(.caption)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 24)
    .padding(.horizontal, 40)
  }
}

// MARK: - Header Content Demo

struct BookTiledViewHeaderContent: View {

  @State private var dataSource = ListDataSource<ChatMessage>()
  @State private var nextPrependId = -1
  @State private var nextAppendId = 0
  @State private var scrollPosition = TiledScrollPosition()
  @State private var isPrependLoading = false

  var body: some View {
    TiledView(
      dataSource: dataSource,
      scrollPosition: $scrollPosition,
      makeInitialState: { _ in ChatBubbleCellState() }
    ) { message in
      ChatBubbleCell(item: message)
    }
    .prependLoader(.loader(
      perform: { /* triggered by button */ },
      isProcessing: isPrependLoading
    ) {
      HStack {
        ProgressView()
        Text("Loading older messages...")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)
      .padding()
    })
    .headerContent(.header {
      ExpandableConversationHeader()
    })
    .toolbar {
      ToolbarItemGroup(placement: .bottomBar) {
        // Toggle Prepend Loading
        Button {
          isPrependLoading.toggle()
          if isPrependLoading {
            Task {
              try? await Task.sleep(for: .seconds(2))
              let messages = generateSampleMessages(count: 5, startId: nextPrependId - 4)
              dataSource.prepend(messages)
              nextPrependId -= 5
              isPrependLoading = false
            }
          }
        } label: {
          Label("Load Older", systemImage: isPrependLoading ? "hourglass" : "arrow.up.doc")
        }

        Spacer()

        // Scroll
        Button {
          scrollPosition.scrollTo(edge: .top)
        } label: {
          Image(systemName: "arrow.up.to.line")
        }

        Button {
          scrollPosition.scrollTo(edge: .bottom)
        } label: {
          Image(systemName: "arrow.down.to.line")
        }

        Spacer()

        // Append
        Button {
          let messages = generateSampleMessages(count: 5, startId: nextAppendId)
          dataSource.append(messages)
          nextAppendId += 5
        } label: {
          Image(systemName: "arrow.down.doc")
        }

        // Reset
        Button {
          nextPrependId = -1
          nextAppendId = 5
          isPrependLoading = false
          let newItems = generateSampleMessages(count: 5, startId: 0)
          dataSource.replace(with: newItems)
        } label: {
          Image(systemName: "arrow.counterclockwise")
        }
      }
    }
    .navigationTitle("Header Content")
  }
}

#Preview("Typing Dots") {
  TypingDotsView()
    .padding()
    .background(Color(.systemGray6))
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .padding()
}

#Preview("Loading Indicators") {
  NavigationStack {
    BookTiledViewLoadingIndicator()
  }
}

#Preview("Typing Indicator") {
  NavigationStack {
    BookTiledViewTypingIndicator()
  }
}

#Preview("Header Content") {
  NavigationStack {
    BookTiledViewHeaderContent()
  }
}
