//
//  OlderMessagesLoadingController.swift
//  swiftui-messaging-ui
//
//  Created by Hiroshi Kimura on 2025/10/23.
//

import SwiftUI
import Combine
import UIKit

@MainActor
final class _OlderMessagesLoadingController: ObservableObject {
  var scrollViewSubscription: AnyCancellable? = nil
  var currentLoadingTask: Task<Void, Never>? = nil

  // For scroll direction detection
  var previousContentOffset: CGFloat? = nil

  // For scroll position preservation
  weak var scrollViewRef: UIScrollView? = nil
  var contentSizeObservation: NSKeyValueObservation? = nil

  // Internal loading state (used when no external binding is provided)
  var internalIsBackwardLoading: Bool = false

  nonisolated init() {}
}
