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
  case applyDiffDemo
  case swiftDataMemo
}

struct ContentView: View {

  @Namespace private var namespace

  var body: some View {
    NavigationStack {
      List {
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
            .navigationTitle("TiledView")
            .navigationBarTitleDisplayMode(.inline)
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
