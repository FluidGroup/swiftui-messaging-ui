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
      Form {
        NavigationLink("Message List Preview") {
          MessageListPreviewContainer()
        }
      }
    }
  }
}

#Preview {
  ContentView()
}
