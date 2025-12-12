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
        Section("Demos") {
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
