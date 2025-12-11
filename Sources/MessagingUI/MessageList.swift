//
//  MessageList.swift
//  swiftui-messaging-ui
//
//  Created by Hiroshi Kimura on 2025/10/23.
//

import SwiftUI
import SwiftUIIntrospect
import Combine

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

  /// Computes the change type for unapplied changes.
  /// Prioritizes prepend if any unapplied change is a prepend.
  private var unappliedChangeType: ListDataSourceChangeType? {
    // Check if DataSource was replaced
    if lastDataSourceID != dataSource.id {
      return .setItems
    }

    let changes = dataSource.pendingChanges
    guard appliedCursor < changes.count else { return nil }

    let unapplied = changes[appliedCursor...]

    // Prioritize prepend for scroll position preservation
    for change in unapplied {
      if case .prepend = change {
        return .prepend
      }
    }

    // Return the first unapplied change type
    return unapplied.first.map { change in
      switch change {
      case .setItems: return .setItems
      case .prepend: return .prepend
      case .append: return .append
      case .update: return .update
      case .remove: return .remove
      }
    }
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 8) {
          ForEach(dataSource.items) { message in
            content(message)
          }
        }
      }
      .scrollPositionPreserving(isPrepending: unappliedChangeType == .prepend)
      .autoScrollToBottom(isEnabled: autoScrollToBottom)
      .onChange(of: dataSource.id) { _, newID in
        // DataSource was replaced, reset cursor
        lastDataSourceID = newID
        appliedCursor = dataSource.pendingChanges.count
      }
      .onChange(of: dataSource.changeCounter) { _, _ in
        // Mark changes as applied after SwiftUI processes the update
        DispatchQueue.main.async {
          appliedCursor = dataSource.pendingChanges.count
        }
      }
      .onAppear {
        // Initialize tracking state
        lastDataSourceID = dataSource.id
        appliedCursor = dataSource.pendingChanges.count
      }
    }
  }
}
