//
//  VisibleMessagesPreference.swift
//  swiftui-messaging-ui
//
//  Created by Hiroshi Kimura on 2025/10/27.
//

import SwiftUI

struct _VisibleMessagePayload {
  var messageId: AnyHashable
  var bounds: Anchor<CGRect>
}

struct _VisibleMessagesPreference: PreferenceKey {
  nonisolated(unsafe) static let defaultValue: [_VisibleMessagePayload] = []

  static func reduce(value: inout [_VisibleMessagePayload], nextValue: () -> [_VisibleMessagePayload]) {
    value.append(contentsOf: nextValue())
  }
}

