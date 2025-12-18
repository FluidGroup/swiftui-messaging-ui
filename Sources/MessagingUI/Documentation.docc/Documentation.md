# ``MessagingUI``

A SwiftUI framework for building messaging interfaces with smooth bidirectional scrolling.

## Overview

MessagingUI provides components for building chat-like interfaces where content can be added
both at the top (older messages) and bottom (newer messages) while maintaining scroll position.

The core component is ``TiledView``, which uses a virtual content space architecture
to enable prepending items without content offset jumps.

### Quick Start

```swift
import MessagingUI

struct ChatView: View {
  @State private var dataSource = ListDataSource<Message>()
  @State private var scrollPosition = TiledScrollPosition()

  var body: some View {
    TiledView(
      dataSource: dataSource,
      scrollPosition: $scrollPosition,
      cellBuilder: { message, state in
        MessageBubble(message: message)
      }
    )
    .task {
      let messages = await fetchMessages()
      dataSource.apply(messages)
    }
  }
}
```

## Topics

### Essentials

- ``TiledView``
- ``ListDataSource``
- ``TiledScrollPosition``

### Architecture

- <doc:TiledView-Architecture>
