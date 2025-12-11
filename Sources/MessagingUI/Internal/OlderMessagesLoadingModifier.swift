//
//  OlderMessagesLoadingModifier.swift
//  swiftui-messaging-ui
//
//  Created by Hiroshi Kimura on 2025/10/23.
//

import SwiftUI
import SwiftUIIntrospect
import UIKit

struct _OlderMessagesLoadingModifier: ViewModifier {
  @StateObject var controller: _OlderMessagesLoadingController = .init()

  private let autoScrollToBottom: Binding<Bool>?
  private let onLoadOlderMessages: (@MainActor () async -> Void)?
  private let lastChangeType: ListDataSourceChangeType?
  private let leadingScreens: CGFloat = 1.0

  nonisolated init(
    autoScrollToBottom: Binding<Bool>?,
    onLoadOlderMessages: (@MainActor () async -> Void)?,
    lastChangeType: ListDataSourceChangeType? = nil
  ) {
    self.autoScrollToBottom = autoScrollToBottom
    self.onLoadOlderMessages = onLoadOlderMessages
    self.lastChangeType = lastChangeType
  }

  func body(content: Content) -> some View {
    // Apply scroll position preservation if either:
    // 1. onLoadOlderMessages is provided (legacy API)
    // 2. lastChangeType is provided (DataSource API)
    if onLoadOlderMessages != nil || lastChangeType != nil {
      if #available(iOS 18.0, macOS 15.0, *) {
        content
          .introspect(.scrollView, on: .iOS(.v18, .v26)) { scrollView in
            // Save reference and setup monitoring
            setupScrollPositionPreservation(scrollView: scrollView)
          }
          .onScrollGeometryChange(for: _GeometryInfo.self) { geometry in
            return _GeometryInfo(
              contentOffset: geometry.contentOffset,
              contentSize: geometry.contentSize,
              containerSize: geometry.containerSize
            )
          } action: { _, geometry in
            let triggers = shouldTriggerLoading(
              contentOffset: geometry.contentOffset.y,
              boundsHeight: geometry.containerSize.height,
              contentHeight: geometry.contentSize.height
            )

            if triggers {
              Task { @MainActor in
                trigger()
              }
            }
          }
      } else {
        content.introspect(.scrollView, on: .iOS(.v17)) { scrollView in
          // Save reference and setup monitoring
          setupScrollPositionPreservation(scrollView: scrollView)

          controller.scrollViewSubscription?.cancel()

          controller.scrollViewSubscription = scrollView.publisher(
            for: \.contentOffset
          )
          .sink { [weak scrollView] offset in
            guard let scrollView else { return }

            let triggers = shouldTriggerLoading(
              contentOffset: offset.y,
              boundsHeight: scrollView.bounds.height,
              contentHeight: scrollView.contentSize.height
            )

            if triggers {
              Task { @MainActor in
                trigger()
              }
            }
          }
        }
      }
    } else {
      content
    }
  }

  private var isBackwardLoading: Bool {
    controller.internalIsBackwardLoading
  }

  private func setBackwardLoading(_ value: Bool) {
    controller.internalIsBackwardLoading = value
  }

  private func shouldTriggerLoading(
    contentOffset: CGFloat,
    boundsHeight: CGFloat,
    contentHeight: CGFloat
  ) -> Bool {
    guard !isBackwardLoading else { return false }
    guard controller.currentLoadingTask == nil else { return false }

    // Check scroll direction
    guard let previousOffset = controller.previousContentOffset else {
      // First time - can't determine direction, just save and skip
      controller.previousContentOffset = contentOffset
      return false
    }

    let isScrollingUp = contentOffset < previousOffset

    // Update previous offset for next comparison
    controller.previousContentOffset = contentOffset

    // Only trigger when scrolling up (towards older messages)
    guard isScrollingUp else {
      return false
    }

    let triggerDistance = boundsHeight * leadingScreens
    let distanceFromTop = contentOffset

    let shouldTrigger = distanceFromTop <= triggerDistance

    return shouldTrigger
  }

  @MainActor
  private func setupScrollPositionPreservation(scrollView: UIScrollView) {

    controller.scrollViewRef = scrollView

    // Clean up existing observations
    controller.contentSizeObservation?.invalidate()

    // Monitor contentSize to detect when content is added (KVO)
    controller.contentSizeObservation = scrollView.observe(
      \.contentSize,
      options: [.old, .new]
    ) { scrollView, change in
      MainActor.assumeIsolated {
        guard let oldHeight = change.oldValue?.height else { return }

        let newHeight = scrollView.contentSize.height
        let heightDiff = newHeight - oldHeight

        // Content size increased
        if heightDiff > 0 {
          let currentOffset = scrollView.contentOffset.y
          let boundsHeight = scrollView.bounds.height

          // Case 1: Loading older messages → preserve scroll position (highest priority)
          // Use lastChangeType from DataSource if available, otherwise fall back to isBackwardLoading flag
          let isPrepending = lastChangeType == .prepend || isBackwardLoading
          if isPrepending {
            let newOffset = currentOffset + heightDiff
            scrollView.contentOffset.y = newOffset
          }
          // Case 2: autoScrollToBottom enabled → scroll to bottom
          else if let autoScrollToBottom = autoScrollToBottom,
            autoScrollToBottom.wrappedValue
          {
            let bottomOffset = newHeight - boundsHeight
            UIView.animate(withDuration: 0.3) {
              scrollView.contentOffset.y = max(0, bottomOffset)
            }
          }
          // Case 3: Normal message addition → do nothing
        }
      }
    }
  }

  @MainActor
  private func trigger() {

    guard let onLoadOlderMessages = onLoadOlderMessages else { return }

    guard !isBackwardLoading else { return }

    guard controller.currentLoadingTask == nil else { return }

    let task = Task { @MainActor in
      await withTaskCancellationHandler {
        setBackwardLoading(true)

        await onLoadOlderMessages()

        // Debounce to avoid rapid re-triggering
        // Ensure the UI has time to update
        try? await Task.sleep(for: .milliseconds(100))

        setBackwardLoading(false)

        controller.currentLoadingTask = nil
      } onCancel: {
        Task { @MainActor in
          setBackwardLoading(false)
          controller.currentLoadingTask = nil
        }
      }

    }

    controller.currentLoadingTask = task
  }
}

// Helper struct for scroll geometry
struct _GeometryInfo: Equatable {
  let contentOffset: CGPoint
  let contentSize: CGSize
  let containerSize: CGSize
}
