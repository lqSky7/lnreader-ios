// WebtoonScrollController.swift - Drives the webtoon strip's scroll view.
//
// The strip itself is a `UICollectionView` (`WebtoonStrip`, below), not a
// SwiftUI `LazyVStack`: a lazy stack guesses the height of rows it has not built
// and corrects the content size as it builds them, which makes scrolling up
// reluctant and jittery. Here every row has an explicit height.
//
// Auto scroll and hold-to-scroll talk to that `UIScrollView` directly: a
// `CADisplayLink` moves `contentOffset`, and the strip reports the current page
// from the offset.
//
// The decisions — how fast, when to stop — live in `ScrollStep` and
// `HoldScrollConfig` (MangaReaderControls.swift). This file only moves pixels.

import SwiftUI
import UIKit

@MainActor
@Observable
final class WebtoonScrollController {

    // MARK: Configuration (set by the reader)

    @ObservationIgnored var autoSpeed: Double = 60
    @ObservationIgnored var hold = HoldScrollConfig()
    @ObservationIgnored var isHoldEnabled = true {
        didSet { holdRecognizer.isEnabled = isHoldEnabled }
    }
    /// Called when auto scroll runs out of content.
    @ObservationIgnored var onReachedEnd: (() -> Void)?
    /// Called while the strip is moving for any reason: drag, hold, auto or a screenful.
    @ObservationIgnored var onScrollActivity: (() -> Void)?
    /// Set by the strip: scrolls the page at this index of that chapter to the top.
    @ObservationIgnored var jumpToPage: ((String, Int) -> Void)?

    // MARK: State (read by the reader's overlay)

    private(set) var isAutoScrolling = false
    /// Current hold speed in points per second, `nil` when not holding.
    private(set) var holdSpeed: Double?

    /// A hold just ended. The finger lifting after a long press looks like a
    /// tap to the reader's tap gesture; this lets it ignore that one.
    var justHeld: Bool { Date().timeIntervalSince(lastHoldEnd) < 0.4 }

    // MARK: Internals

    @ObservationIgnored private weak var scrollView: UIScrollView?
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval = 0
    @ObservationIgnored private var holdStartY: CGFloat = 0
    @ObservationIgnored private var lastHoldEnd = Date.distantPast
    @ObservationIgnored private var hapticTracker: HoldHapticTracker?
    @ObservationIgnored private let tickFeedback = UISelectionFeedbackGenerator()
    @ObservationIgnored private let limitFeedback = UIImpactFeedbackGenerator(style: .rigid)
    @ObservationIgnored private lazy var proxy = Proxy(owner: self)
    @ObservationIgnored private lazy var holdRecognizer: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: proxy, action: #selector(Proxy.held(_:)))
        recognizer.minimumPressDuration = 0.3
        // Only governs the wait: a finger that travels this far before the
        // press registers is a scroll, and the recognizer steps aside.
        recognizer.allowableMovement = 10
        recognizer.delegate = proxy
        recognizer.isEnabled = isHoldEnabled
        return recognizer
    }()

    // MARK: - Attaching

    /// Bind to the scroll view the strip is rendered in. Called again when the
    /// strip is rebuilt (new chapter), so the previous one is released.
    func attach(_ view: UIScrollView) {
        guard scrollView !== view else { return }
        scrollView?.removeGestureRecognizer(holdRecognizer)
        scrollView = view
        view.addGestureRecognizer(holdRecognizer)
        updateLink()
    }

    func detach() {
        stopAuto()
        endHold()
        scrollView?.removeGestureRecognizer(holdRecognizer)
        scrollView = nil
    }

    // MARK: - Auto scroll

    func startAuto() {
        guard scrollView != nil, !isAutoScrolling else { return }
        isAutoScrolling = true
        updateLink()
    }

    func stopAuto() {
        guard isAutoScrolling else { return }
        isAutoScrolling = false
        updateLink()
    }

    func toggleAuto() {
        if isAutoScrolling { stopAuto() } else { startAuto() }
    }

    // MARK: - Paging by a screenful

    /// Scroll roughly one screen, for the volume keys.
    func scrollScreen(forward: Bool, fraction: CGFloat = 0.85) {
        guard let view = scrollView else { return }
        let inset = view.adjustedContentInset
        let minY = -inset.top
        let maxY = max(minY, view.contentSize.height - view.bounds.height + inset.bottom)
        let delta = view.bounds.height * fraction * (forward ? 1 : -1)
        let target = min(max(view.contentOffset.y + delta, minY), maxY)
        view.setContentOffset(CGPoint(x: view.contentOffset.x, y: target), animated: true)
        onScrollActivity?()
    }

    // MARK: - Hold to scroll

    fileprivate func holdBegan(at y: CGFloat) {
        guard let view = scrollView else { return }
        holdStartY = y
        let start = hold.speed(forDrag: 0)
        holdSpeed = start
        hapticTracker = hold.haptics ? HoldHapticTracker(startSpeed: start, config: hold) : nil
        tickFeedback.prepare()
        limitFeedback.prepare()
        // The hold owns the finger from here: a drag changes the speed, it
        // does not also drag the content.
        view.panGestureRecognizer.isEnabled = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        updateLink()
    }

    fileprivate func holdMoved(to y: CGFloat) {
        guard holdSpeed != nil else { return }
        let speed = hold.speed(forDrag: Double(y - holdStartY))
        holdSpeed = speed
        switch hapticTracker?.update(speed: speed, config: hold) {
        case .tick: tickFeedback.selectionChanged()
        case .limit: limitFeedback.impactOccurred()
        case nil: break
        }
    }

    fileprivate func endHold() {
        guard holdSpeed != nil else { return }
        holdSpeed = nil
        hapticTracker = nil
        lastHoldEnd = Date()
        scrollView?.panGestureRecognizer.isEnabled = true
        updateLink()
    }

    // MARK: - Frame loop

    /// The display link only runs while something is scrolling.
    private func updateLink() {
        let needed = scrollView != nil && (isAutoScrolling || holdSpeed != nil)
        if needed, link == nil {
            let displayLink = CADisplayLink(target: proxy, selector: #selector(Proxy.frame(_:)))
            lastTimestamp = 0
            displayLink.add(to: .main, forMode: .common)
            link = displayLink
        } else if !needed, let existing = link {
            existing.invalidate()
            link = nil
        }
    }

    fileprivate func tick(_ displayLink: CADisplayLink) {
        guard let view = scrollView else { return stopAll() }
        let dt = lastTimestamp == 0 ? 0 : displayLink.timestamp - lastTimestamp
        lastTimestamp = displayLink.timestamp

        let speed: Double
        if let holdSpeed {
            speed = holdSpeed
        } else if isAutoScrolling, !view.isTracking, !view.isDragging, !view.isDecelerating {
            // The reader's own finger always wins: auto scroll waits for the
            // drag and its momentum to finish, then carries on.
            speed = autoSpeed
        } else {
            return
        }

        let inset = view.adjustedContentInset
        let maxY = max(-inset.top, view.contentSize.height - view.bounds.height + inset.bottom)
        let step = ScrollStep.advance(
            offset: Double(view.contentOffset.y),
            speed: speed,
            dt: dt,
            maxOffset: Double(maxY)
        )
        view.contentOffset.y = CGFloat(step.offset)
        onScrollActivity?()

        if step.reachedEnd, holdSpeed == nil, isAutoScrolling {
            stopAuto()
            onReachedEnd?()
        }
    }

    private func stopAll() {
        isAutoScrolling = false
        holdSpeed = nil
        updateLink()
    }

    // MARK: - Objective-C bridge

    /// `CADisplayLink` and gesture recognizers need an `NSObject` target, which
    /// an `@Observable` class is not. Holds the owner weakly, so the display
    /// link retaining its target is not a retain cycle.
    private final class Proxy: NSObject, UIGestureRecognizerDelegate {
        weak var owner: WebtoonScrollController?
        init(owner: WebtoonScrollController) { self.owner = owner }

        @objc func frame(_ link: CADisplayLink) {
            MainActor.assumeIsolated { owner?.tick(link) }
        }

        @objc func held(_ recognizer: UILongPressGestureRecognizer) {
            MainActor.assumeIsolated {
                // Window coordinates: the content moves under the finger while
                // it scrolls, so a point in the scroll view would drift.
                let y = recognizer.location(in: nil).y
                switch recognizer.state {
                case .began: owner?.holdBegan(at: y)
                case .changed: owner?.holdMoved(to: y)
                case .ended, .cancelled, .failed: owner?.endHold()
                default: break
                }
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }
}
