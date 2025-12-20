# swiftui-messaging-ui

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FFluidGroup%2Fswiftui-messaging-ui%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/FluidGroup/swiftui-messaging-ui)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FFluidGroup%2Fswiftui-messaging-ui%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/FluidGroup/swiftui-messaging-ui)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/FluidGroup/swiftui-messaging-ui)

A primitive component to make Chat-UI with **stable prepending** - no scroll jumps when loading older messages.

| Auto Scrolling | Prepending without jumps | Revealing Info |
| :--- | :--- | :-- |
| ![video2](https://github.com/user-attachments/assets/e21ff76e-5b39-45b2-b13b-c608d15414e7)| ![video1](https://github.com/user-attachments/assets/5325bbd0-38bc-4504-868d-e379b2ba3f2f) | ![Simulator Screen Recording - iPhone 17 Pro - 2025-12-19 at 15 45 00](https://github.com/user-attachments/assets/fa654218-9104-4737-ba23-8677c0955fc1) |

| Loading Indicator (top, bottom) | Typing Indicator |
| :--- | :--- |
| ![Simulator Screen Recording - iPhone 17 Pro - 2025-12-20 at 04 27 17](https://github.com/user-attachments/assets/469cde0e-0ba7-4c0d-bebf-91824970787e) | ![Simulator Screen Recording - iPhone 17 Pro - 2025-12-21 at 04 55 24](https://github.com/user-attachments/assets/7235161e-3fb2-4f47-92b2-0c044587b8c2) |

## The Prepending Problem

Standard SwiftUI `List` and `ScrollView` cause **scroll position jumps** when prepending items. In chat apps, loading older messages creates jarring visual shifts as content is inserted above the current view.

### contentOffset Adjustment is Fragile

A common workaround is adjusting `contentOffset` after prepending. However, this requires:
- Precise timing of when prepend operations complete
- Exact knowledge of inserted content height before layout
- Careful handling when multiple operations occur together (prepend + update + remove)

In practice, this approach breaks easily with complex data flows.

### The Virtual Layout Solution

This library takes a different approach: a **virtual content layout** with a 100-million-point content space where items are anchored at the center. Prepending simply extends content upward without ever changing `contentOffset`, eliminating the timing and coordination problems entirely.

## Key Features

- **Smooth Prepend/Append** - No scroll jumps when loading older or newer messages
- **UICollectionView-backed** - Native recycling with SwiftUI cell rendering
- **Self-Sizing Cells** - Automatic height calculation for variable content
- **Keyboard & Safe Area Handling** - Automatic content inset adjustment for keyboard and safe areas
- **Typing Indicator** 

## Requirements

- iOS 17.0+
- Swift 6.0+
- Xcode 26.0+

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
  .package(url: "https://github.com/FluidGroup/swiftui-messaging-ui", from: "1.0.0")
]
```

Or add it through Xcode:
1. File > Add Package Dependencies
2. Enter the repository URL: `https://github.com/FluidGroup/swiftui-messaging-ui`

## Usage

### Basic Example

```swift
import MessagingUI
import SwiftUI

struct Message: Identifiable, Equatable {
  let id: Int
  var text: String
  var isFromMe: Bool
  var timestamp: Date
}

// Define your cell using TiledCellContent protocol
struct MessageBubbleCell: TiledCellContent {
  typealias StateValue = Void  // No per-cell state needed
  let item: Message

  func body(context: CellContext<Void>) -> some View {
    HStack {
      if item.isFromMe { Spacer() }
      Text(item.text)
        .padding(12)
        .background(item.isFromMe ? Color.blue : Color.gray.opacity(0.3))
        .foregroundStyle(item.isFromMe ? .white : .primary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
      if !item.isFromMe { Spacer() }
    }
    .padding(.horizontal)
  }
}

struct ChatView: View {
  @State private var dataSource = ListDataSource<Message>()
  @State private var scrollPosition = TiledScrollPosition()

  var body: some View {
    TiledView(
      dataSource: dataSource,
      scrollPosition: $scrollPosition
    ) { message in
      MessageBubbleCell(item: message)
    }
    .task {
      dataSource.apply(initialMessages)
    }
  }
}
```

### Loading Older Messages

Use `prependLoader` to handle loading older messages with a built-in loading indicator:

```swift
TiledView(
  dataSource: dataSource,
  scrollPosition: $scrollPosition,
  prependLoader: .loader(perform: {
    // Called when user scrolls near the top
    let olderMessages = await fetchOlderMessages()
    dataSource.prepend(olderMessages)
  }) {
    // Loading indicator shown while loading
    ProgressView()
  }
) { message in
  MessageBubbleCell(item: message)
}
```

Similarly, use `appendLoader` for loading newer messages at the bottom.

#### Sync Mode with External State

If you need to control the loading state externally:

```swift
@State private var isLoading = false

TiledView(
  dataSource: dataSource,
  scrollPosition: $scrollPosition,
  prependLoader: .loader(
    perform: { loadOlderMessages() },
    isProcessing: isLoading
  ) {
    ProgressView()
  }
) { message in
  MessageBubbleCell(item: message)
}
```

### Programmatic Scrolling

```swift
@State private var scrollPosition = TiledScrollPosition()

// Scroll to bottom
Button("Scroll to Bottom") {
  scrollPosition.scrollTo(edge: .bottom)
}

// Scroll to top
Button("Scroll to Top") {
  scrollPosition.scrollTo(edge: .top, animated: false)
}
```

### Swipe to Reveal Timestamps

iMessage-style horizontal swipe gesture to reveal timestamps. Use `CellContext` to access the reveal offset:

```swift
struct MessageBubbleCell: TiledCellContent {
  typealias StateValue = Void
  let item: Message

  func body(context: CellContext<Void>) -> some View {
    // Get the reveal offset with rubber band effect
    let offset = context.cellReveal?.rubberbandedOffset(max: 60) ?? 0

    HStack(alignment: .bottom, spacing: 8) {
      if item.isFromMe {
        Spacer()
        // Timestamp fades in as user swipes
        Text(item.timestamp, style: .time)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .opacity(offset / 40)

        MessageBubble(message: item)
          .offset(x: -offset)  // Slide left to reveal
      } else {
        MessageBubble(message: item)
          .offset(x: -offset)

        Text(item.timestamp, style: .time)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .opacity(offset / 40)
        Spacer()
      }
    }
  }
}
```

To disable the reveal gesture:

```swift
TiledView(...)
  .revealConfiguration(.disabled)
```

### Typing Indicator

Show when other users are typing with the `typingIndicator` parameter:

```swift
TiledView(
  dataSource: dataSource,
  scrollPosition: $scrollPosition,
  typingIndicator: .indicator(isVisible: store.isTyping) {
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
  MessageBubbleCell(item: message)
}
```

The typing indicator appears below the last message and automatically scrolls into view when it appears (if the user is near the bottom of the list).

### Observing Scroll Position

Use `onTiledScrollGeometryChange` to observe scroll position changes. This is useful for showing "scroll to bottom" buttons or enabling/disabling auto-scroll:

```swift
@State private var showScrollButton = false

TiledView(...)
  .onTiledScrollGeometryChange { geometry in
    // Show button when user scrolls up from bottom
    showScrollButton = geometry.pointsFromBottom > 100

    // Dynamically enable auto-scroll only when near bottom
    scrollPosition.autoScrollsToBottomOnAppend = geometry.pointsFromBottom < 100
  }
```

### Auto-Scroll Configuration

Configure automatic scrolling behavior for messaging UIs:

```swift
@State private var scrollPosition = TiledScrollPosition(
  autoScrollsToBottomOnAppend: true,   // Auto-scroll when new messages arrive
  scrollsToBottomOnReplace: true       // Start at bottom on initial load
)
```

### Per-Cell State

Manage UI state (like expanded/collapsed, tap counts) that persists across cell reuse using `CellStateStorage`. This is ideal for cell-specific state that isn't part of your data model.

> **Important: Why Not @State?**
>
> You can use `@State` inside cell views, but the state will be lost when the cell is reused. `TiledView` uses `UICollectionView` which recycles cells for performance. When a cell scrolls off-screen and is reused for a different item, any `@State` values are reset. Use `CellStateStorage` for state that should persist.

#### Basic Usage

```swift
struct MyCellState {
  var isExpanded: Bool = false
  var tapCount: Int = 0
}

struct MessageCell: TiledCellContent {
  typealias StateValue = MyCellState
  let item: Message

  func body(context: CellContext<MyCellState>) -> some View {
    VStack {
      Text(item.text)

      if context.state.value.isExpanded {
        Text("Additional details...")
      }

      Button("Expand") {
        context.state.value.isExpanded.toggle()
      }
    }
  }
}

// Provide initial state factory
TiledView(
  dataSource: dataSource,
  scrollPosition: $scrollPosition,
  makeInitialState: { item in MyCellState() }
) { message in
  MessageCell(item: message)
}
```

#### Using Reference Types

`StateValue` can be a reference type like `@Observable` classes for more complex state management:

```swift
@Observable
final class CellViewModel {
  var isExpanded = false
  var loadedData: Data?

  func loadData() async { ... }
}

struct MessageCell: TiledCellContent {
  typealias StateValue = CellViewModel
  let item: Message

  func body(context: CellContext<CellViewModel>) -> some View {
    let viewModel = context.state.value
    // Use viewModel directly - @Observable handles updates
    Text(viewModel.isExpanded ? "Expanded" : "Collapsed")
  }
}
```

#### Sharing State Across All Cells

To share state across all cells (e.g., selection state), return the same instance in `makeInitialState`:

```swift
@Observable
final class SharedSelectionState {
  var selectedIds: Set<Message.ID> = []
}

struct ChatView: View {
  @State private var dataSource = ListDataSource<Message>()
  @State private var scrollPosition = TiledScrollPosition()
  @State private var sharedState = SharedSelectionState()

  var body: some View {
    TiledView(
      dataSource: dataSource,
      scrollPosition: $scrollPosition,
      makeInitialState: { _ in sharedState }  // Same instance for all cells
    ) { message in
      SelectableMessageCell(item: message)
    }
  }
}
```

#### State Lifecycle

- **Creation**: State is lazily created when a cell is first displayed
- **Persistence**: State persists for the lifetime of the `TiledView`, even if items are temporarily removed
- **Destruction**: State is released when the `TiledView` is destroyed

> **Note**: If an item is removed and later re-added with the same ID, it will retain its previous state. This behavior may change in future versions with configurable lifecycle options.
