# Swipe to Reveal Timestamps

Implement iMessage-style horizontal swipe gesture to reveal timestamps on messages.

## Overview

In iMessage, users can swipe left on a conversation to reveal timestamps for each message.
This gesture provides a clean UI where timestamps are hidden by default but easily accessible.

```
Default State:                    Revealed State (swipe left):
┌─────────────────────────┐       ┌─────────────────────────┐
│                         │       │                         │
│            ┌──────────┐ │       │   10:30  ┌──────────┐   │
│            │ Hello!   │ │  →    │     AM   │ Hello!   │   │
│            └──────────┘ │       │          └──────────┘   │
│                         │       │                         │
│ ┌──────────┐            │       │ ┌──────────┐  10:31     │
│ │ Hi there │            │  →    │ │ Hi there │    AM      │
│ └──────────┘            │       │ └──────────┘            │
│                         │       │                         │
└─────────────────────────┘       └─────────────────────────┘
```

TiledView provides built-in support for this gesture through the ``TiledCellContent`` protocol.

## Basic Implementation

### Step 1: Create a Cell Conforming to TiledCellContent

Conform to ``TiledCellContent`` and use the `context` parameter to access the reveal offset:

```swift
import MessagingUI

struct MessageBubbleCell: TiledCellContent {
  let item: Message

  /// Maximum offset before rubber banding kicks in
  private let maxRevealOffset: CGFloat = 60

  func body(context: CellContext) -> some View {
    let offset = context.cellReveal?.rubberbandedOffset(max: maxRevealOffset) ?? 0

    HStack(alignment: .bottom, spacing: 8) {
      if item.isFromMe {
        Spacer(minLength: 60)

        // Timestamp (revealed on swipe)
        Text(item.timestamp, style: .time)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .opacity(offset / 40)  // Fade in as user swipes

        // Message bubble
        MessageBubble(text: item.text, isFromMe: true)
          .offset(x: -offset)  // Move left to reveal timestamp
      } else {
        // Message bubble
        MessageBubble(text: item.text, isFromMe: false)
          .offset(x: -offset)

        // Timestamp (revealed on swipe)
        Text(item.timestamp, style: .time)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .opacity(offset / 40)

        Spacer(minLength: 60)
      }
    }
  }
}
```

### Step 2: Use in TiledView

The reveal gesture is enabled by default. Simply return your cell from the builder:

```swift
struct ChatView: View {
  @State private var dataSource = ListDataSource<Message>()
  @State private var scrollPosition = TiledScrollPosition()

  var body: some View {
    TiledView(
      dataSource: dataSource,
      scrollPosition: $scrollPosition
    ) { message, state in
      MessageBubbleCell(item: message)
    }
  }
}
```

## How It Works

### TiledCellContent Protocol

``TiledCellContent`` provides a clean way to build cells that respond to reveal gestures:

```swift
public protocol TiledCellContent {
  associatedtype Item
  associatedtype Body: View

  var item: Item { get }

  func body(context: CellContext) -> Body
}
```

The `context` parameter provides access to ``CellContext/cellReveal``, which holds the current
reveal offset shared across all cells.

### CellContext

``CellContext`` is passed to your `body(context:)` method and provides cell-related state:

```swift
func body(context: CellContext) -> some View {
  // Access the reveal state
  let offset = context.cellReveal?.rubberbandedOffset(max: 60) ?? 0
  // ...
}
```

### Rubber Banding

The `rubberbandedOffset(max:)` method applies a rubber band effect when the offset exceeds
the maximum value. This provides natural resistance as the user swipes beyond the intended range.

```swift
// Without rubber banding: offset keeps increasing linearly
// With rubber banding: offset slows down after reaching max

let offset = context.cellReveal?.rubberbandedOffset(max: 80) ?? 0
//                                                   ↑
//                                    Rubber banding starts at 80pt
```

### Gesture Detection

TiledView uses angle-based gesture detection to distinguish between:
- **Vertical scroll**: Normal scrolling through messages
- **Horizontal swipe**: Reveal gesture

The gesture is recognized as a reveal only when the initial movement is predominantly horizontal
and to the left. This prevents accidental reveals during normal scrolling.

## Configuration

### Disabling the Reveal Gesture

If you don't need the reveal feature, disable it:

```swift
TiledView(...)
  .revealConfiguration(.disabled)
```

## Design Patterns

### Different Max Offsets per Cell Type

Each cell can specify its own max offset for rubber banding:

```swift
struct SentMessageCell: TiledCellContent {
  let item: Message

  func body(context: CellContext) -> some View {
    // Sent messages reveal timestamp on the left
    let offset = context.cellReveal?.rubberbandedOffset(max: 60) ?? 0
    // ...
  }
}

struct SystemMessageCell: TiledCellContent {
  let item: SystemEvent

  func body(context: CellContext) -> some View {
    // System messages might need more space for longer timestamps
    let offset = context.cellReveal?.rubberbandedOffset(max: 100) ?? 0
    // ...
  }
}
```

### Animating Other Properties

Use the offset to animate any property, not just position:

```swift
func body(context: CellContext) -> some View {
  let offset = context.cellReveal?.rubberbandedOffset(max: 60) ?? 0

  HStack {
    MessageBubble(text: item.text)
      .offset(x: -offset)
      .scaleEffect(1 - offset / 500)  // Subtle shrink effect

    Text(item.timestamp.formatted())
      .opacity(offset / 30)           // Fade in
      .offset(x: 20 - offset / 3)     // Slide in from right
  }
}
```

## Handling nil cellReveal

`cellReveal` is `nil` when:
1. The view is not inside a `TiledView`
2. Reveal is disabled via `.revealConfiguration(.disabled)`

Always provide a fallback:

```swift
let offset = context.cellReveal?.rubberbandedOffset(max: 60) ?? 0
```

This ensures your cell renders correctly in previews and when reveal is disabled.

## Alternative: Using @Environment

If you prefer not to use the protocol, you can access the reveal state directly
via `@Environment`:

```swift
struct MessageBubbleView: View {
  let message: Message

  @Environment(\.cellReveal) private var cellReveal

  var body: some View {
    let offset = cellReveal?.rubberbandedOffset(max: 60) ?? 0
    // ...
  }
}
```

## See Also

- ``TiledCellContent``
- ``CellContext``
- ``CellReveal``
- ``RevealConfiguration``
- ``TiledView``
