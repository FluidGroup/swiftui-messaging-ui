# TiledView Architecture

A deep dive into TiledView's virtual content space design for bidirectional infinite scrolling.

## Overview

TiledView is a UICollectionView-based component that enables bidirectional infinite scrolling.
Like chat UIs, it supports adding content both upward (older messages) and downward (newer messages).

## Core Concept: Virtual Content Space

### Basic Design

```
┌─────────────────────────────────────┐
│                                     │
│     Virtual Content Space           │
│     (100,000,000 pixels)            │
│                                     │
│  ┌─────────────────────────────┐    │
│  │                             │    │
│  │  Prepend Area               │    │
│  │  (items added to top)       │    │
│  │                             │    │
│  ├─────────────────────────────┤    │  ← anchorY (50,000,000)
│  │                             │    │
│  │  Initial Items              │    │
│  │                             │    │
│  ├─────────────────────────────┤    │
│  │                             │    │
│  │  Append Area                │    │
│  │  (items added to bottom)    │    │
│  │                             │    │
│  └─────────────────────────────┘    │
│                                     │
└─────────────────────────────────────┘
```

### Why This Design?

In a standard UICollectionView, adding items at the beginning causes the `contentOffset` to shift,
making the user's view position jump unexpectedly.

The traditional solution is to adjust `contentOffset` after prepending, but this has problems:

1. Visual jumps or flickering may occur
2. Difficult to adjust during animations
3. Race conditions may occur depending on timing

**Virtual Content Space design** never changes `contentOffset`.
Instead, it uses a huge virtual space (100 million pixels) with an anchor point at the center (50 million pixels),
and adjusts the Y positions of items themselves.

### Prepend Behavior

```
Before:                          After:
┌──────────┐                     ┌──────────┐
│ Item 0   │ y=50000000          │ New Item │ y=49999900 (= 50000000 - 100)
├──────────┤                     ├──────────┤
│ Item 1   │ y=50000100          │ Item 0   │ y=50000000 (unchanged)
├──────────┤                     ├──────────┤
│ Item 2   │ y=50000200          │ Item 1   │ y=50000100 (unchanged)
└──────────┘                     ├──────────┤
                                 │ Item 2   │ y=50000200 (unchanged)
                                 └──────────┘

contentOffset: unchanged (user's view position stays the same)
```

New items are placed **above** existing items, and existing item Y positions remain unchanged.
Since `contentOffset` also remains unchanged, the user's view position is perfectly maintained.

### Append Behavior

```
Before:                          After:
┌──────────┐                     ┌──────────┐
│ Item 0   │ y=50000000          │ Item 0   │ y=50000000 (unchanged)
├──────────┤                     ├──────────┤
│ Item 1   │ y=50000100          │ Item 1   │ y=50000100 (unchanged)
├──────────┤                     ├──────────┤
│ Item 2   │ y=50000200          │ Item 2   │ y=50000200 (unchanged)
└──────────┘                     ├──────────┤
                                 │ New Item │ y=50000300 (= 50000200 + 100)
                                 └──────────┘
```

---

## Architecture Components

### Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ TiledView (SwiftUI View)                                    │
│   - dataSource: ListDataSource<Item>                        │
│   - scrollPosition: TiledScrollPosition                     │
│   - cellBuilder: (Item, CellState) -> Cell                  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ _TiledView<Item, Cell> (UIView)                             │
│   - items: Deque<Item>                                      │
│   - cellBuilder: (Item, CellState) -> Cell                  │
│   - sizingHostingController: UIHostingController<Cell?>     │
│                                                             │
│   Applies changes from ListDataSource:                      │
│   - .replace → reload all                                   │
│   - .prepend → add items above                              │
│   - .append → add items below                               │
│   - .update → refresh specific cells                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ TiledCollectionViewLayout (UICollectionViewLayout)          │
│   - itemYPositions: [CGFloat]                               │
│   - itemHeights: [CGFloat]                                  │
│   - itemSizeProvider: ((Int, CGFloat) -> CGSize?)?          │
│                                                             │
│   Methods:                                                  │
│   - appendItems(count:startingIndex:)                       │
│   - prependItems(count:)                                    │
│   - updateItemHeight(at:newHeight:)                         │
└─────────────────────────────────────────────────────────────┘
```

### Usage Example

```swift
struct ChatView: View {
  @State private var dataSource = ListDataSource<Message>()
  @State private var scrollPosition = TiledScrollPosition()

  var body: some View {
    TiledView(
      dataSource: dataSource,
      scrollPosition: $scrollPosition,
      onPrepend: { await loadOlderMessages() },
      cellBuilder: { message, state in
        MessageBubble(message: message)
      }
    )
    .task {
      let messages = await fetchInitialMessages()
      dataSource.apply(messages)
    }
  }

  func loadOlderMessages() async {
    let older = await fetchOlderMessages()
    dataSource.prepend(older)
  }
}
```

### Cell Size Measurement with itemSizeProvider

To get accurate sizes before cells are displayed, TiledView uses an `itemSizeProvider` closure.

```swift
// Inside TiledView
tiledLayout.itemSizeProvider = { [weak self] index, width in
  self?.measureSize(at: index, width: width)
}

// Size measurement (reusing UIHostingController)
private func measureSize(at index: Int, width: CGFloat) -> CGSize? {
  guard index < items.count else { return nil }
  let item = items[index]
  sizingHostingController.rootView = cellBuilder(item, .init())
  sizingHostingController.view.layoutIfNeeded()

  return sizingHostingController.view.systemLayoutSizeFitting(
    CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
    withHorizontalFittingPriority: .required,
    verticalFittingPriority: .fittingSizeLevel
  )
}
```

**Important**: Creating a new `UIHostingController` instance each time is expensive.
A single instance is retained and its `rootView` is swapped for reuse.

---

## Design Constraints

### Absolute Constraints

1. **contentOffset is never changed**
   - This is the foundation of the Virtual Content Space architecture
   - Changing this would require redesigning the entire architecture

2. **Layout must explicitly know prepend/append**
   - Y position calculation direction differs
   - Prepend: Place above existing items (Y position decreases)
   - Append: Place below existing items (Y position increases)

### Implementation Constraints

1. **Synchronization between items array and Layout arrays**
   - `items` and `TiledCollectionViewLayout.itemYPositions/itemHeights` must always be in sync
   - Order: Update items array first → Then update Layout

2. **Size measurement timing**
   - `itemSizeProvider` is called after the items array is updated
   - `measureSize` accesses the items array, so order is important

---

## Why Declarative API is Challenging

### The Goal

```swift
// Ideal declarative API
struct ChatView: View {
  @State private var messages: [Message] = []

  var body: some View {
    TiledView(items: messages) { message in
      MessageBubble(message: message)
    }
  }

  func loadOlder() {
    messages.insert(contentsOf: olderMessages, at: 0)  // Just modify state
  }
}
```

### The Fundamental Problem

SwiftUI's declarative API only provides "current state".
However, TiledCollectionViewLayout needs to know "prepend vs append".

```
SwiftUI World:                    Layout World:
─────────────────                 ─────────────────
"Here are the items"              "Where did the new items go?"
[A, B, C, D, E]                   - Prepend? → Y positions shift up
                                  - Append? → Y positions extend down
                                  - Insert in middle? → ???
```

### Solution: ListDataSource

``ListDataSource`` solves this by tracking changes explicitly:

```swift
// Instead of modifying arrays directly:
messages.insert(contentsOf: older, at: 0)  // SwiftUI can't tell this was prepend

// Use ListDataSource which tracks the change type:
dataSource.prepend(older)  // Explicitly tells Layout it's a prepend

// Or use apply() which auto-detects:
dataSource.apply(newMessages)  // Compares and detects prepend/append/update
```

---

## File Structure

```
Sources/MessagingUI/
├── ListDataSource.swift          - Change-tracking data source
├── Tiled/
│   ├── TiledView.swift
│   │   ├── TiledViewCell         - UICollectionViewCell with UIHostingConfiguration
│   │   ├── _TiledView            - Main UIView component
│   │   └── TiledView             - SwiftUI wrapper
│   │
│   ├── TiledCollectionViewLayout.swift
│   │   └── TiledCollectionViewLayout - Custom layout with virtual content space
│   │
│   └── TiledScrollPosition.swift - Scroll position control
```

---

## References

- [UICollectionViewLayout](https://developer.apple.com/documentation/uikit/uicollectionviewlayout)
- [UIHostingConfiguration](https://developer.apple.com/documentation/swiftui/uihostingconfiguration)
