//
//  AutoScrollToBottomModifier.swift
//  MessagingUI
//
//  Created by Hiroshi Kimura on 2025/12/11.
//

import SwiftUI
import SwiftUIIntrospect
import UIKit

/// A view modifier that automatically scrolls to the bottom when content is added.
///
/// When enabled and new content increases the scroll view's content size,
/// this modifier animates the scroll position to the bottom.
struct _AutoScrollToBottomModifier: ViewModifier {

  @StateObject private var controller = _AutoScrollToBottomController()

  private let isEnabled: Binding<Bool>?

  init(isEnabled: Binding<Bool>?) {
    self.isEnabled = isEnabled
  }

  func body(content: Content) -> some View {
    Group {
      if #available(iOS 18.0, macOS 15.0, *) {
        content
          .introspect(.scrollView, on: .iOS(.v18, .v26)) { scrollView in
            setupContentSizeObservation(scrollView: scrollView)
          }
      } else {
        content
          .introspect(.scrollView, on: .iOS(.v17)) { scrollView in
            setupContentSizeObservation(scrollView: scrollView)
          }
      }
    }
    .onAppear {
      controller.isEnabled = isEnabled
    }
  }

  @MainActor
  private func setupContentSizeObservation(scrollView: UIScrollView) {
    guard controller.scrollViewRef !== scrollView else { return }

    controller.scrollViewRef = scrollView
    controller.contentSizeObservation?.invalidate()

    let controller = self.controller

    controller.contentSizeObservation = scrollView.observe(
      \.contentSize,
      options: [.old, .new]
    ) { scrollView, change in
      MainActor.assumeIsolated {
        guard let oldHeight = change.oldValue?.height else { return }

        let newHeight = scrollView.contentSize.height
        let heightDiff = newHeight - oldHeight

        // Content size increased and auto-scroll is enabled
        if heightDiff > 0,
          let isEnabled = controller.isEnabled,
          isEnabled.wrappedValue
        {
          let boundsHeight = scrollView.bounds.height
          let bottomOffset = newHeight - boundsHeight
          UIView.animate(withDuration: 0.3) {
            scrollView.contentOffset.y = max(0, bottomOffset)
          }
        }
      }
    }
  }
}

@MainActor
private final class _AutoScrollToBottomController: ObservableObject {
  weak var scrollViewRef: UIScrollView?
  var contentSizeObservation: NSKeyValueObservation?
  var isEnabled: Binding<Bool>?
}

// MARK: - View Extension

extension View {
  /// Automatically scrolls to the bottom when content is added.
  ///
  /// - Parameter isEnabled: Binding that controls whether auto-scroll is active.
  func autoScrollToBottom(isEnabled: Binding<Bool>?) -> some View {
    modifier(_AutoScrollToBottomModifier(isEnabled: isEnabled))
  }
}
