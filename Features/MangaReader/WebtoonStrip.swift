// WebtoonStrip.swift - The webtoon's vertical strip, as a collection view.
//
// A SwiftUI `LazyVStack` guesses the height of rows it has not built and
// corrects the content size as it builds them, which makes scrolling up
// reluctant and jittery. Here every row has an explicit height: the page's real
// aspect ratio once known (read from the image header), a guess until then.

import SwiftUI
import UIKit

/// One chapter's pages in the strip. Chapters are stitched end to end, each
/// followed by a divider card naming the next one.
struct WebtoonSegment {
    /// The chapter's URL.
    let id: String
    let pages: [SourcePage]
    /// Title of the chapter that follows; `nil` when there is none, which also drops the divider.
    let nextTitle: String?
}

/// What a row of the strip shows.
private enum WebtoonItem {
    case page(segment: Int, index: Int, page: SourcePage)
    /// The divider after a segment. `loading` while the next chapter is still being fetched.
    case divider(segment: Int, title: String, loading: Bool)
}

struct WebtoonStrip: UIViewControllerRepresentable {
    let segments: [WebtoonSegment]
    let sourceKey: String
    let loader: PageLoader
    /// Page of the first segment to open on. Only read when the strip is built.
    let startIndex: Int
    /// Page width as a share of the screen; the rest is still margin.
    let widthFraction: CGFloat
    let controller: WebtoonScrollController
    /// The page at the top of the screen changed: its chapter and index in it.
    let onPageChange: (String, Int) -> Void
    /// The divider after this chapter became fully visible; `nil` when none is.
    let onEndCard: (String?) -> Void
    /// A tap, in the strip's own (screen) coordinates.
    let onTap: (CGPoint) -> Void

    func makeUIViewController(context: Context) -> WebtoonViewController {
        let vc = WebtoonViewController(startIndex: startIndex, controller: controller)
        apply(to: vc)
        return vc
    }

    func updateUIViewController(_ vc: WebtoonViewController, context: Context) {
        apply(to: vc)
    }

    private func apply(to vc: WebtoonViewController) {
        vc.sourceKey = sourceKey
        vc.loader = loader
        vc.onPageChange = onPageChange
        vc.onEndCard = onEndCard
        vc.onTap = onTap
        vc.setWidthFraction(widthFraction)
        vc.update(segments: segments)
    }
}

@MainActor
final class WebtoonViewController: UIViewController,
    UICollectionViewDataSource, UICollectionViewDelegateFlowLayout,
    UICollectionViewDataSourcePrefetching, UIGestureRecognizerDelegate {

    /// Height guess for a page whose size is not known yet. Real heights come
    /// from the first bytes of the image (`PageImageCache.aspectRatios`) and
    /// replace it without moving what is on screen.
    private static let fallbackRatio: CGFloat = 0.7
    private static let dividerHeight: CGFloat = 220

    var sourceKey = ""
    var loader: PageLoader?
    var onPageChange: ((String, Int) -> Void)?
    var onEndCard: ((String?) -> Void)?
    var onTap: ((CGPoint) -> Void)?

    private let startIndex: Int
    private let controller: WebtoonScrollController
    private var segments: [WebtoonSegment] = []
    private var items: [WebtoonItem] = []
    private var indexByURL: [String: [Int]] = [:]

    private let layout = UICollectionViewFlowLayout()
    private var collectionView: UICollectionView!
    private var didRestore = false
    private var lastReported: Int
    private var endCardSegment: String?
    private var lastWidth: CGFloat = 0
    private var widthFraction: CGFloat = 1
    private var pendingRatios: Set<Int> = []
    private var flushScheduled = false
    private var observer: NSObjectProtocol?
    private var touchStoppedScroll = false
    private var lastScrollTime: CFTimeInterval = 0
    private var speedometer = ScrollSpeedometer()
    private var detents = ScrollDetents()
    private var chapterMarks = ScrollChapterMarks()
    private var edgeBump = ScrollEdgeBump()

    init(startIndex: Int, controller: WebtoonScrollController) {
        self.startIndex = startIndex
        self.lastReported = startIndex
        self.controller = controller
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .black
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.isPrefetchingEnabled = true
        collectionView.register(WebtoonPageCell.self, forCellWithReuseIdentifier: WebtoonPageCell.reuseID)
        collectionView.register(WebtoonEndCell.self, forCellWithReuseIdentifier: WebtoonEndCell.reuseID)
        view.addSubview(collectionView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        collectionView.addGestureRecognizer(tap)

        controller.attach(collectionView)
        Haptics.shared.prepare()
        controller.jumpToPage = { [weak self] chapter, index in
            guard let self, let item = self.items.firstIndex(where: {
                if case let .page(segment, pageIndex, _) = $0 {
                    return self.segments[segment].id == chapter && pageIndex == index
                }
                return false
            }) else { return }
            self.jump(to: item)
        }

        observer = NotificationCenter.default.addObserver(
            forName: PageImageCache.ratioLearned, object: nil, queue: .main
        ) { [weak self] note in
            guard let key = note.object as? String else { return }
            MainActor.assumeIsolated { self?.ratioLearned(forURL: key) }
        }
    }

    // MARK: Data

    func update(segments newSegments: [WebtoonSegment]) {
        let same = newSegments.count == segments.count && zip(newSegments, segments).allSatisfy { new, old in
            new.id == old.id && new.nextTitle == old.nextTitle && new.pages.count == old.pages.count
                && zip(new.pages, old.pages).allSatisfy { $0.url == $1.url }
        }
        guard !same else { return }
        // A chapter added at the end leaves every existing row where it was, so
        // only the new rows are inserted; reloading all of them mid-scroll hitches.
        let appended = newSegments.count > segments.count && !segments.isEmpty
            && zip(newSegments, segments).allSatisfy { new, old in
                new.id == old.id && new.nextTitle == old.nextTitle && new.pages.count == old.pages.count
                    && zip(new.pages, old.pages).allSatisfy { $0.url == $1.url }
            }
        let oldCount = items.count
        segments = newSegments
        var built: [WebtoonItem] = []
        var lookup: [String: [Int]] = [:]
        for (segment, entry) in newSegments.enumerated() {
            for (index, page) in entry.pages.enumerated() {
                lookup[page.url, default: []].append(built.count)
                built.append(.page(segment: segment, index: index, page: page))
            }
            if let title = entry.nextTitle {
                built.append(.divider(segment: segment, title: title, loading: segment == newSegments.count - 1))
            }
        }
        items = built
        indexByURL = lookup
        guard isViewLoaded else { return }
        guard appended, built.count > oldCount else { return collectionView.reloadData() }
        // The divider that was last stops showing its spinner.
        let refreshed = items[..<oldCount].indices.last.flatMap { index -> IndexPath? in
            if case .divider = items[index] { return IndexPath(item: index, section: 0) }
            return nil
        }
        UIView.performWithoutAnimation {
            collectionView.performBatchUpdates {
                collectionView.insertItems(at: (oldCount..<built.count).map { IndexPath(item: $0, section: 0) })
                if let refreshed { collectionView.reloadItems(at: [refreshed]) }
            }
        }
    }

    private var itemCount: Int { items.count }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { itemCount }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch items[indexPath.item] {
        case let .divider(_, title, loading):
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: WebtoonEndCell.reuseID, for: indexPath) as! WebtoonEndCell
            cell.show(title: title, loading: loading)
            return cell
        case let .page(_, _, page):
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: WebtoonPageCell.reuseID, for: indexPath) as! WebtoonPageCell
            if let loader {
                // Decoded for the full screen width whatever the strip width:
                // the cache keeps one bitmap per page, and widening the strip
                // again must not stretch one decoded for a narrower strip.
                cell.show(
                    page: page,
                    sourceKey: sourceKey,
                    loader: loader,
                    targetWidth: collectionView.bounds.width * traitCollection.displayScale,
                    scale: traitCollection.displayScale
                )
            }
            return cell
        }
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        guard let loader else { return }
        let wanted: [SourcePage] = indexPaths.compactMap {
            if case let .page(_, _, page) = items[$0.item] { return page }
            return nil
        }
        PagePrerender.prime(
            wanted,
            sourceKey: sourceKey,
            loader: loader,
            targetWidth: collectionView.bounds.width * traitCollection.displayScale,
            screenScale: traitCollection.displayScale
        )
    }

    // MARK: Sizing

    private func height(forItem item: Int, width: CGFloat) -> CGFloat {
        guard case let .page(_, _, page) = items[item] else { return Self.dividerHeight }
        let ratio = PageImageCache.aspectRatios[page.url] ?? Self.fallbackRatio
        let scale = max(traitCollection.displayScale, 1)
        // Whole device pixels, so neighbouring pages never leave a seam.
        return (width / max(ratio, 0.01) * scale).rounded() / scale
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let width = max(pageWidth, 1)
        return CGSize(width: width, height: height(forItem: indexPath.item, width: width))
    }

    /// The strip's width in whole device pixels, so its edges never blur.
    private var pageWidth: CGFloat {
        let scale = max(traitCollection.displayScale, 1)
        return (collectionView.bounds.width * widthFraction * scale).rounded() / scale
    }

    /// Centre the strip between equal margins. The collection view itself stays
    /// full width, so a drag or tap in the margin still scrolls.
    private func applyMargins() {
        let side = max(0, (collectionView.bounds.width - pageWidth) / 2)
        layout.sectionInset = UIEdgeInsets(top: 0, left: side, bottom: 0, right: side)
    }

    /// Narrow or widen the strip, keeping the same spot of the same page at
    /// the top of the screen.
    func setWidthFraction(_ fraction: CGFloat) {
        guard fraction != widthFraction else { return }
        guard isViewLoaded, collectionView.bounds.width > 0, itemCount > 0 else {
            widthFraction = fraction
            return
        }
        let top = collectionView.contentOffset.y
        let anchor = collectionView.indexPathForItem(at: CGPoint(x: collectionView.bounds.midX, y: top + 0.5))
        let progress = anchor.flatMap { layout.layoutAttributesForItem(at: $0)?.frame }
            .map { ($0.height > 0 ? (top - $0.minY) / $0.height : 0) } ?? 0

        widthFraction = fraction
        applyMargins()
        layout.invalidateLayout()
        collectionView.layoutIfNeeded()

        guard let anchor, let frame = layout.layoutAttributesForItem(at: anchor)?.frame else { return }
        let target = min(max(frame.minY + progress * frame.height, 0), maxOffsetY)
        collectionView.setContentOffset(CGPoint(x: 0, y: target), animated: false)
    }

    /// A page's real aspect ratio just became known. Resize its slot; if the
    /// slot is above the screen, shift the offset by the same amount so what the
    /// reader is looking at does not move.
    private func ratioLearned(forURL url: String) {
        guard let indices = indexByURL[url] else { return }
        pendingRatios.formUnion(indices)
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.async { [weak self] in self?.flushRatios() }
    }

    private func flushRatios() {
        flushScheduled = false
        let indices = pendingRatios
        pendingRatios = []
        let width = pageWidth
        guard width > 0 else { return }

        let top = collectionView.contentOffset.y
        var adjustment: CGFloat = 0
        var changed = false
        for index in indices {
            guard let old = layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame else { continue }
            let delta = height(forItem: index, width: width) - old.height
            guard abs(delta) >= 0.5 else { continue }
            changed = true
            if old.minY < top { adjustment += delta }
        }
        guard changed else { return }

        let context = UICollectionViewFlowLayoutInvalidationContext()
        context.invalidateFlowLayoutDelegateMetrics = true
        context.contentOffsetAdjustment = CGPoint(x: 0, y: adjustment)
        layout.invalidateLayout(with: context)
    }

    // MARK: Layout and position

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = collectionView.bounds.width
        guard width > 0 else { return }
        if lastWidth != width {
            lastWidth = width
            applyMargins()
            layout.invalidateLayout()
        }
        if !didRestore, itemCount > 0 {
            didRestore = true
            if startIndex > 0 { jump(to: startIndex) }
        }
    }

    private var maxOffsetY: CGFloat {
        max(0, collectionView.contentSize.height - collectionView.bounds.height)
    }

    private func jump(to index: Int) {
        guard itemCount > 0 else { return }
        collectionView.layoutIfNeeded()
        let item = min(max(index, 0), itemCount - 1)
        guard let frame = layout.layoutAttributesForItem(at: IndexPath(item: item, section: 0))?.frame else { return }
        collectionView.setContentOffset(CGPoint(x: 0, y: min(frame.minY, maxOffsetY)), animated: false)
    }

    // MARK: Reporting

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        lastScrollTime = CACurrentMediaTime()
        guard didRestore else { return }
        let userDriven = scrollView.isDragging || scrollView.isDecelerating
        if userDriven { controller.onScrollActivity?() }
        let top = scrollView.contentOffset.y
        let bottom = top + scrollView.bounds.height
        playScrollHaptics(top: top, userDriven: userDriven)

        var current: Int?
        var endSegment: String?
        for path in collectionView.indexPathsForVisibleItems.sorted() {
            guard let frame = layout.layoutAttributesForItem(at: path)?.frame, frame.height > 0 else { continue }
            let visible = min(frame.maxY, bottom) - max(frame.minY, top)
            switch items[path.item] {
            case let .divider(segment, _, _):
                if visible >= frame.height * 0.95 { endSegment = segments[segment].id }
            case .page:
                if current == nil, visible >= frame.height * 0.05 { current = path.item }
            }
        }
        // At the very bottom the top row can be a page or two short of the last
        // one; the reader has still reached it.
        if top >= maxOffsetY - 1, let last = items.indices.last, case .page = items[last] {
            current = last
        }
        if let current, current != lastReported, case let .page(segment, index, _) = items[current] {
            lastReported = current
            onPageChange?(segments[segment].id, index)
        }
        if endSegment != endCardSegment {
            endCardSegment = endSegment
            onEndCard?(endSegment)
        }
    }

    // MARK: Haptics

    /// A steady tick as the strip moves, a chapter cue as a divider reaches the
    /// middle of the screen, a thud on running into either end. Only for the
    /// reader's own drag and its momentum: hold, auto scroll and jumps are silent.
    private func playScrollHaptics(top: CGFloat, userDriven: Bool) {
        let now = CACurrentMediaTime()
        let speed = speedometer.sample(offset: Double(top), time: now)
        let line = CGPoint(x: collectionView.bounds.midX, y: top + collectionView.bounds.height / 2)
        let row = collectionView.indexPathForItem(at: line)?.item
        var isDivider = false
        if let row, items.indices.contains(row), case .divider = items[row] { isDivider = true }
        // Every tracker sees every frame, so none loses its place when another fires.
        let detent = detents.update(offset: Double(top), speed: speed, time: now, userDriven: userDriven)
        let chapter = chapterMarks.update(row: row, isChapterBreak: isDivider, speed: speed, userDriven: userDriven)
        let edge = edgeBump.update(offset: Double(top), minOffset: 0, maxOffset: Double(maxOffsetY),
                                   speed: speed, userDriven: userDriven)
        if let cue = edge ?? chapter ?? detent { Haptics.shared.scroll(cue) }
    }

    // MARK: Taps

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        // A finger that landed to stop the strip is not a tap: it would hit a
        // tap zone and scroll a screenful the moment the reader stops to read.
        guard !touchStoppedScroll else { return }
        onTap?(gesture.location(in: view))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // The scroll view halts its momentum as the touch lands, so by the time
        // the tap is recognised it no longer says it was moving; remember it now.
        touchStoppedScroll = collectionView.isDecelerating
            || collectionView.isDragging
            || CACurrentMediaTime() - lastScrollTime < 0.1
        return !(touch.view is UIControl)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { true }
}
