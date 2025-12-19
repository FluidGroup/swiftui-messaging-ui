# Bidirectional Loading

Implement infinite scrolling in both directions for messaging apps that open at a specific point.

## Overview

Many messaging apps need to open conversations at a specific message (e.g., search results, notifications, or unread markers). This requires loading content in both directions as the user scrolls.

```
                    ↑ Scroll up → Load older messages (onPrepend)
┌─────────────────────────────────────┐
│                                     │
│  ┌─────────────────────────────┐    │
│  │ Older messages              │    │
│  │ (loaded on demand)          │    │
│  ├─────────────────────────────┤    │
│  │                             │    │
│  │ Initially loaded messages   │    │  ← User opens here
│  │ (centered around target)    │    │
│  │                             │    │
│  ├─────────────────────────────┤    │
│  │ Newer messages              │    │
│  │ (loaded on demand)          │    │
│  └─────────────────────────────┘    │
│                                     │
└─────────────────────────────────────┘
                    ↓ Scroll down → Load newer messages (onAppend)
```

## Basic Usage

Use `onPrepend` and `onAppend` callbacks to trigger loading:

```swift
TiledView(
  dataSource: dataSource,
  scrollPosition: $scrollPosition,
  onPrepend: {
    await loadOlderMessages()
  },
  onAppend: {
    await loadNewerMessages()
  }
) { message, state in
  MessageBubble(message: message)
}
```

- **onPrepend**: Called when the user scrolls near the top (within 100pt)
- **onAppend**: Called when the user scrolls near the bottom (within 100pt)

Both callbacks can run concurrently without issues.

## Window-Based Pagination Pattern

For database-backed apps, use a window-based approach with offset/limit instead of cursor-based pagination:

```
All messages in database: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]  (totalCount = 10)
                              ↑           ↑
                        windowStart=2  windowEnd=7

Currently loaded: [2, 3, 4, 5, 6]  (windowSize = 5)

hasMore = (windowStart > 0) = true      → Can load older
hasNewer = (windowEnd < totalCount) = true  → Can load newer
```

### Implementation Example

```swift
@Observable
final class MessageStore {
  private let modelContext: ModelContext
  private(set) var dataSource = ListDataSource<MessageItem>()

  // Window state
  private(set) var totalCount = 0
  private var windowStart: Int = 0
  private var windowSize: Int = 0
  private let pageSize = 20

  // Computed properties for load state
  var hasMore: Bool { windowStart > 0 }
  var hasNewer: Bool { windowStart + windowSize < totalCount }

  /// Load initial messages from a specific position
  func loadInitial(from position: LoadPosition) {
    totalCount = fetchTotalCount()

    switch position {
    case .end:
      // Start from newest messages
      windowStart = max(0, totalCount - pageSize)
      windowSize = min(pageSize, totalCount)
    case .middle:
      // Start from middle
      windowStart = max(0, totalCount / 2 - pageSize / 2)
      windowSize = min(pageSize, totalCount - windowStart)
    }

    refreshWindow()
  }

  /// Load older messages (prepend direction)
  func loadOlder() {
    guard hasMore else { return }
    let prepend = min(pageSize, windowStart)
    windowStart -= prepend
    windowSize += prepend
    refreshWindow()
  }

  /// Load newer messages (append direction)
  func loadNewer() {
    guard hasNewer else { return }
    let available = totalCount - (windowStart + windowSize)
    let append = min(pageSize, available)
    windowSize += append
    refreshWindow()
  }

  private func refreshWindow() {
    var descriptor = FetchDescriptor<MessageModel>(
      sortBy: [SortDescriptor(\.timestamp, order: .forward)]
    )
    descriptor.fetchOffset = windowStart
    descriptor.fetchLimit = windowSize

    let models = (try? modelContext.fetch(descriptor)) ?? []
    dataSource.apply(models.map(MessageItem.init))
  }
}
```

### Why Window-Based Instead of Cursor-Based?

Cursor-based pagination (using timestamps or IDs) can have issues:

1. **Timestamp collisions**: Multiple messages with the same timestamp may cause missed items
2. **Sort stability**: Database sort order may vary between queries
3. **Complexity**: Need to track both oldest and newest cursors

Window-based pagination with offset/limit is simpler and more reliable when you have a stable sort order.

## Handling New Messages

When new messages arrive while viewing from the middle:

```swift
func receiveMessage(text: String) {
  // Insert into database
  let message = MessageModel(text: text, ...)
  modelContext.insert(message)
  try? modelContext.save()

  totalCount += 1

  // If already at the end, extend window to include new message
  if !hasNewer {
    windowSize += 1
  }
  // Otherwise, hasNewer becomes true and user can scroll to see it

  refreshWindow()
}
```

## Scroll Position Configuration

Configure `TiledScrollPosition` based on the initial load position:

```swift
struct ChatView: View {
  let loadPosition: LoadPosition
  @State private var scrollPosition: TiledScrollPosition

  init(loadPosition: LoadPosition) {
    self.loadPosition = loadPosition
    self._scrollPosition = State(initialValue: TiledScrollPosition(
      // Only auto-scroll when loading from end
      autoScrollsToBottomOnAppend: loadPosition == .end,
      scrollsToBottomOnReplace: loadPosition == .end
    ))
  }
}
```

## Complete Example

See `MessengerSwiftDataDemo` in the development app for a complete implementation with:
- SwiftData persistence
- Bidirectional loading
- Message sending/receiving
- Status bar showing load state
