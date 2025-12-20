//
//  ContentView.swift
//  MessagingUIDevelopment
//
//  Created by Hiroshi Kimura on 2025/10/27.
//

import SwiftUI
import MessagingUI

enum DemoDestination: Hashable {
  case tiledView
  case tiledViewLoadingIndicator
  case tiledViewTypingIndicator
  case lazyVStack
  case list
  case messenger
  case messengerSwiftData
  case messengerBidirectional
  case applyDiffDemo
  case swiftDataMemo
}

struct ContentView: View {

  @Namespace private var namespace

  var body: some View {
    NavigationStack {
      List {
        Section("Featured") {
          NavigationLink(value: DemoDestination.messengerSwiftData) {
            Label {
              VStack(alignment: .leading) {
                Text("Messenger + SwiftData")
                Text("Persistent chat with status")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "message.badge.checkmark.fill")
            }
          }
        }

        Section("Demos") {
          NavigationLink(value: DemoDestination.tiledView) {
            Label {
              VStack(alignment: .leading) {
                Text("TiledView")
                Text("UICollectionView based")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "square.grid.2x2")
            }
          }

          NavigationLink(value: DemoDestination.tiledViewLoadingIndicator) {
            Label {
              VStack(alignment: .leading) {
                Text("Loading Indicators")
                Text("Header/Footer loading spinners")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
            }
          }

          NavigationLink(value: DemoDestination.tiledViewTypingIndicator) {
            Label {
              VStack(alignment: .leading) {
                Text("Typing Indicator")
                Text("Show typing status at bottom")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "ellipsis.bubble")
            }
          }

          NavigationLink(value: DemoDestination.lazyVStack) {
            Label {
              VStack(alignment: .leading) {
                Text("LazyVStack")
                Text("SwiftUI native")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "list.bullet")
            }
          }

          NavigationLink(value: DemoDestination.list) {
            Label {
              VStack(alignment: .leading) {
                Text("List")
                Text("SwiftUI List")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "list.bullet.rectangle")
            }
          }

          NavigationLink(value: DemoDestination.messenger) {
            Label {
              VStack(alignment: .leading) {
                Text("Messenger")
                Text("Chat bubble demo")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "message.fill")
            }
          }

          NavigationLink(value: DemoDestination.applyDiffDemo) {
            Label {
              VStack(alignment: .leading) {
                Text("applyDiff Demo")
                Text("Auto-detect array changes")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "arrow.triangle.2.circlepath")
            }
          }
        }

        Section("SwiftData Integration") {
          NavigationLink(value: DemoDestination.messengerBidirectional) {
            Label {
              VStack(alignment: .leading) {
                Text("Messenger (Bidirectional)")
                Text("Load from middle, scroll both ways")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "arrow.up.arrow.down")
            }
          }

          NavigationLink(value: DemoDestination.swiftDataMemo) {
            Label {
              VStack(alignment: .leading) {
                Text("Memo Stream")
                Text("SwiftData + TiledView pagination")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "note.text")
            }
          }
        }
      }
      .navigationTitle("MessagingUI")
      .navigationDestination(for: DemoDestination.self) { destination in
        switch destination {
        case .tiledView:
          BookTiledView(namespace: namespace)       
        case .tiledViewLoadingIndicator:
          BookTiledViewLoadingIndicator()
            .navigationBarTitleDisplayMode(.inline)
        case .tiledViewTypingIndicator:
          BookTiledViewTypingIndicator()
            .navigationBarTitleDisplayMode(.inline)
        case .lazyVStack:
          LazyVStackDemo()
        case .list:
          ListDemo()
        case .messenger:
          MessengerDemo()
        case .messengerSwiftData:
          MessengerSwiftDataDemo()
        case .messengerBidirectional:
          MessengerSwiftDataDemo(loadPosition: .middle)
        case .applyDiffDemo:
          BookApplyDiffDemo()
            .navigationTitle("applyDiff Demo")
            .navigationBarTitleDisplayMode(.inline)
        case .swiftDataMemo:
          SwiftDataMemoDemo()
            .navigationBarTitleDisplayMode(.inline)
        }
      }
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
}

#Preview {
  ContentView()
}
