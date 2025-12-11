//
//  ScrollPositionPreservingModifier.swift
//  MessagingUI
//
//  Created by Hiroshi Kimura on 2025/12/11.
//

import SwiftUI
import SwiftUIIntrospect
import UIKit

/// A view modifier that preserves scroll position when content is prepended.
///
/// When new content is added at the top of a scroll view, this modifier adjusts
/// the content offset to maintain the user's current scroll position.
struct _ScrollPositionPreservingModifier: ViewModifier {

  @StateObject private var controller = _ScrollPositionPreservingController()

  private let isPrepending: Bool

  init(isPrepending: Bool) {
    self.isPrepending = isPrepending
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
    .onChange(of: isPrepending) { _, newValue in
      controller.isPrepending = newValue
    }
    .onAppear {
      controller.isPrepending = isPrepending
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

        // Content size increased and we're prepending
        if heightDiff > 0 && controller.isPrepending {
          let newOffset = scrollView.contentOffset.y + heightDiff
          scrollView.contentOffset.y = newOffset
        }
      }
    }
  }
}

@MainActor
private final class _ScrollPositionPreservingController: ObservableObject {
  weak var scrollViewRef: UIScrollView?
  var contentSizeObservation: NSKeyValueObservation?
  var isPrepending: Bool = false
}

// MARK: - View Extension

extension View {
  /// Preserves scroll position when content is prepended.
  ///
  /// - Parameter isPrepending: Whether content is currently being prepended.
  func scrollPositionPreserving(isPrepending: Bool) -> some View {
    modifier(_ScrollPositionPreservingModifier(isPrepending: isPrepending))
  }
}
