//
//  ContentView.swift
//  MessagingUIDevelopment
//
//  Created by Hiroshi Kimura on 2025/10/27.
//

import SwiftUI

struct ContentView: View {
  var body: some View {
    NavigationStack {
      List {
        Section("List Implementation Comparison") {
          NavigationLink {
            BookSideBySideComparison()
              .navigationTitle("Side by Side")
              .navigationBarTitleDisplayMode(.inline)
          } label: {
            Label {
              VStack(alignment: .leading) {
                Text("Side by Side")
                Text("Same DataSource, split view")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "rectangle.split.2x1")
            }
          }

          NavigationLink {
            BookListComparison()
              .navigationTitle("Tab Comparison")
              .navigationBarTitleDisplayMode(.inline)
          } label: {
            Label {
              VStack(alignment: .leading) {
                Text("Tab Comparison")
                Text("Separate DataSource, tab switch")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "arrow.left.arrow.right")
            }
          }
        }

        Section("Individual Demos") {
          NavigationLink {
            BookTiledView()
              .navigationTitle("TiledView")
              .navigationBarTitleDisplayMode(.inline)
          } label: {
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

          NavigationLink {
            BookMessageList()
              .navigationTitle("MessageList")
              .navigationBarTitleDisplayMode(.inline)
          } label: {
            Label {
              VStack(alignment: .leading) {
                Text("MessageList")
                Text("LazyVStack based")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "list.bullet")
            }
          }

          NavigationLink {
            BookApplyDiffDemo()
              .navigationTitle("applyDiff Demo")
              .navigationBarTitleDisplayMode(.inline)
          } label: {
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

        Section("Other Examples") {
          NavigationLink {
            MessageListPreviewContainer()
              .navigationTitle("Chat Style")
              .navigationBarTitleDisplayMode(.inline)
          } label: {
            Label {
              VStack(alignment: .leading) {
                Text("Chat Style Demo")
                Text("Simple chat bubbles")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "bubble.left.and.bubble.right")
            }
          }
        }

        Section("SwiftData Integration") {
          NavigationLink {
            SwiftDataMemoDemo()
              .navigationBarTitleDisplayMode(.inline)
          } label: {
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
    }
  }
}

#Preview {
  ContentView()
}
