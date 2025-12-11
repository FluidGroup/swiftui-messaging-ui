//
//  MessageList.swift
//  swiftui-messaging-ui
//
//  Created by Hiroshi Kimura on 2025/10/23.
//

import SwiftUI

/// Change type for MessageList to track prepend/append operations.
public enum ListDataSourceChangeType: Equatable, Sendable {
  case setItems
  case prepend
  case append
  case update
  case remove
}

/// # Spec
///
/// - `MessageList` is a generic, scrollable message list component that displays messages using a custom view builder.
/// - Keeps short lists anchored to the bottom of the scroll view.
/// - Supports loading older messages by scrolling up, with an optional loading indicator at the top.
///
/// ## Usage
///
/// ```swift
/// @State private var dataSource = ListDataSource<ChatMessage>(items: messages)
///
/// MessageList(dataSource: dataSource) { message in
///   Text(message.text)
///     .padding(12)
///     .background(Color.blue.opacity(0.1))
///     .cornerRadius(8)
/// }
/// ```
public struct MessageList<Message: Identifiable & Equatable, Content: View>: View {

  private let dataSource: ListDataSource<Message>
  private let content: (Message) -> Content
  private let autoScrollToBottom: Binding<Bool>?

  /// Creates a message list using a ListDataSource for change tracking.
  ///
  /// This initializer automatically detects prepend/append operations from the
  /// data source's change history, enabling proper scroll position preservation.
  ///
  /// - Parameters:
  ///   - dataSource: A ListDataSource that tracks changes for efficient updates.
  ///   - autoScrollToBottom: Optional binding that controls automatic scrolling to bottom when new messages are added.
  ///   - content: A view builder that creates the view for each message.
  public init(
    dataSource: ListDataSource<Message>,
    autoScrollToBottom: Binding<Bool>? = nil,
    @ViewBuilder content: @escaping (Message) -> Content
  ) {
    self.dataSource = dataSource
    self.content = content
    self.autoScrollToBottom = autoScrollToBottom
  }

  public var body: some View {
    _MessageListContent(
      dataSource: dataSource,
      autoScrollToBottom: autoScrollToBottom,
      content: content
    )
  }
}

// MARK: - Internal Content View with State

private struct _MessageListContent<Message: Identifiable & Equatable, Content: View>: View {

  let dataSource: ListDataSource<Message>
  let autoScrollToBottom: Binding<Bool>?
  let content: (Message) -> Content

  /// Tracks which changes have been applied (cursor into pendingChanges)
  @State private var appliedCursor: Int = 0
  /// Tracks the last DataSource ID to detect replacement
  @State private var lastDataSourceID: UUID?
  /// Anchor message ID to preserve scroll position during prepend
  @State private var anchorMessageID: Message.ID?
  /// Flag to indicate we're in a prepend operation
  @State private var isPrepending: Bool = false

  var body: some View {
    ScrollViewReader { proxy in
      scrollContent
        .defaultScrollAnchor(.bottom)
        .modifier(ContentSizeChangeModifier(
          isPrepending: $isPrepending,
          anchorMessageID: $anchorMessageID,
          autoScrollToBottom: autoScrollToBottom,
          lastItemID: dataSource.items.last?.id,
          proxy: proxy
        ))
        .onChange(of: dataSource.id) { _, newID in
          // DataSource was replaced, reset cursor
          lastDataSourceID = newID
          appliedCursor = dataSource.pendingChanges.count
          isPrepending = false
          anchorMessageID = nil
        }
        .onChange(of: dataSource.changeCounter) { _, _ in
          handleDataSourceChange()
        }
        .onAppear {
          // Initialize tracking state
          lastDataSourceID = dataSource.id
          appliedCursor = dataSource.pendingChanges.count
        }
    }
  }

  private var scrollContent: some View {
    ScrollView {
      LazyVStack(spacing: 8) {
        ForEach(dataSource.items) { message in
          content(message)
            .id(message.id)
        }
      }
    }
  }

  private func handleDataSourceChange() {
    // Check if any pending change is prepend
    let hasPrepend = dataSource.pendingChanges[appliedCursor...].contains {
      if case .prepend = $0 { return true }
      return false
    }

    if hasPrepend {
      // Remember the first item to anchor to after prepend
      // After prepend, this item will no longer be at index 0
      if let firstVisibleID = dataSource.items.first?.id {
        anchorMessageID = firstVisibleID
      }
      isPrepending = true
    } else {
      isPrepending = false
      anchorMessageID = nil
    }

    // Update cursor
    appliedCursor = dataSource.pendingChanges.count
  }
}

// MARK: - Content Size Change Modifier

private struct ContentSizeChangeModifier<ID: Hashable>: ViewModifier {
  @Binding var isPrepending: Bool
  @Binding var anchorMessageID: ID?
  let autoScrollToBottom: Binding<Bool>?
  let lastItemID: ID?
  let proxy: ScrollViewProxy

  func body(content: Content) -> some View {
    if #available(iOS 18.0, *) {
      content
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
          geometry.contentSize.height
        } action: { oldHeight, newHeight in
          handleContentSizeChange(oldHeight: oldHeight, newHeight: newHeight)
        }
    } else {
      // iOS 17: No onScrollGeometryChange, use onChange of data as fallback
      content
        .onChange(of: anchorMessageID) { _, newValue in
          // When anchorMessageID is set and then layout happens,
          // scroll to anchor on next run loop
          if isPrepending, let anchorID = newValue {
            DispatchQueue.main.async {
              proxy.scrollTo(anchorID, anchor: .top)
              isPrepending = false
              anchorMessageID = nil
            }
          }
        }
        .onChange(of: lastItemID) { _, newValue in
          // Auto-scroll to bottom on append
          if let autoScrollToBottom,
             autoScrollToBottom.wrappedValue,
             !isPrepending,
             let lastID = newValue {
            withAnimation(.easeOut(duration: 0.3)) {
              proxy.scrollTo(lastID, anchor: .bottom)
            }
          }
        }
    }
  }

  private func handleContentSizeChange(oldHeight: CGFloat, newHeight: CGFloat) {
    let heightDiff = newHeight - oldHeight
    guard heightDiff > 0 else { return }

    if isPrepending, let anchorID = anchorMessageID {
      // Prepend: Scroll to anchor message to preserve position
      proxy.scrollTo(anchorID, anchor: .top)
      isPrepending = false
      anchorMessageID = nil
    } else if let autoScrollToBottom,
              autoScrollToBottom.wrappedValue,
              !isPrepending {
      // Append: Auto-scroll to bottom
      if let lastID = lastItemID {
        withAnimation(.easeOut(duration: 0.3)) {
          proxy.scrollTo(lastID, anchor: .bottom)
        }
      }
    }
  }
}
