// WebtoonStrip.swift - The webtoon's vertical strip, as a collection view.
//
// A SwiftUI `LazyVStack` guesses the height of rows it has not built and
// corrects the content size as it builds them, which makes scrolling up
// reluctant and jittery. Here every row has an explicit height: the page's real
// aspect ratio once known (read from the image header), a guess until then.

import SwiftUI
import UIKit

struct WebtoonStrip: UIViewControllerRepresentable {
    let pages: [SourcePage]
    let sourceKey: String
    let loader: PageLoader
    /// Page to open on. Only read when the strip is built.
    let startIndex: Int
    /// Title of the next chapter; `nil` when there is none, which also drops the end card.
    let nextChapterTitle: String?
    let controller: WebtoonScrollController
    /// The page at the top of the screen changed.
    let onPageChange: (Int) -> Void
    /// The end card became fully visible or stopped being.
    let onEndCard: (Bool) -> Void
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
        vc.update(pages: pages, nextChapterTitle: nextChapterTitle)
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

    var sourceKey = ""
    var loader: PageLoader?
    var onPageChange: ((Int) -> Void)?
    var onEndCard: ((Bool) -> Void)?
    var onTap: ((CGPoint) -> Void)?

    private let startIndex: Int
    private let controller: WebtoonScrollController
    private var pages: [SourcePage] = []
    private var nextChapterTitle: String?
    private var indexByURL: [String: Int] = [:]

    private let layout = UICollectionViewFlowLayout()
    private var collectionView: UICollectionView!
    private var didRestore = false
    private var lastReported: Int
    private var endCardVisible = false
    private var lastWidth: CGFloat = 0
    private var pendingRatios: Set<Int> = []
    private var flushScheduled = false
    private var observer: NSObjectProtocol?
    private var touchStoppedScroll = false
    private var lastScrollTime: CFTimeInterval = 0

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
        controller.jumpToPage = { [weak self] index in self?.jump(to: index) }

        observer = NotificationCenter.default.addObserver(
            forName: PageImageCache.ratioLearned, object: nil, queue: .main
        ) { [weak self] note in
            guard let key = note.object as? String else { return }
            MainActor.assumeIsolated { self?.ratioLearned(forURL: key) }
        }
    }

    // MARK: Data

    func update(pages newPages: [SourcePage], nextChapterTitle title: String?) {
        let samePages = newPages.count == pages.count
            && zip(newPages, pages).allSatisfy { $0.url == $1.url }
        guard !samePages || title != nextChapterTitle else { return }
        pages = newPages
        nextChapterTitle = title
        indexByURL = Dictionary(newPages.enumerated().map { ($1.url, $0) }, uniquingKeysWith: { first, _ in first })
        if isViewLoaded { collectionView.reloadData() }
    }

    private var itemCount: Int { pages.count + (nextChapterTitle == nil ? 0 : 1) }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { itemCount }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if indexPath.item >= pages.count {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: WebtoonEndCell.reuseID, for: indexPath) as! WebtoonEndCell
            cell.show(title: nextChapterTitle ?? "")
            return cell
        }
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: WebtoonPageCell.reuseID, for: indexPath) as! WebtoonPageCell
        if let loader {
            cell.show(
                page: pages[indexPath.item],
                sourceKey: sourceKey,
                loader: loader,
                targetWidth: collectionView.bounds.width * traitCollection.displayScale,
                scale: traitCollection.displayScale
            )
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        guard let loader else { return }
        let wanted = indexPaths.map(\.item).filter { pages.indices.contains($0) }.map { pages[$0] }
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
        if item >= pages.count { return max(collectionView.bounds.height * 0.5, 240) }
        let ratio = PageImageCache.aspectRatios[pages[item].url] ?? Self.fallbackRatio
        let scale = max(traitCollection.displayScale, 1)
        // Whole device pixels, so neighbouring pages never leave a seam.
        return (width / max(ratio, 0.01) * scale).rounded() / scale
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let width = max(collectionView.bounds.width, 1)
        return CGSize(width: width, height: height(forItem: indexPath.item, width: width))
    }

    /// A page's real aspect ratio just became known. Resize its slot; if the
    /// slot is above the screen, shift the offset by the same amount so what the
    /// reader is looking at does not move.
    private func ratioLearned(forURL url: String) {
        guard let index = indexByURL[url] else { return }
        pendingRatios.insert(index)
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.async { [weak self] in self?.flushRatios() }
    }

    private func flushRatios() {
        flushScheduled = false
        let indices = pendingRatios
        pendingRatios = []
        let width = collectionView.bounds.width
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
        if scrollView.isDragging || scrollView.isDecelerating { controller.onScrollActivity?() }
        let top = scrollView.contentOffset.y
        let bottom = top + scrollView.bounds.height

        var current: Int?
        var endVisible = false
        for path in collectionView.indexPathsForVisibleItems.sorted() {
            guard let frame = layout.layoutAttributesForItem(at: path)?.frame, frame.height > 0 else { continue }
            let visible = min(frame.maxY, bottom) - max(frame.minY, top)
            if path.item >= pages.count {
                endVisible = visible >= frame.height * 0.95
            } else if current == nil, visible >= frame.height * 0.05 {
                current = path.item
            }
        }
        if let current, current != lastReported {
            lastReported = current
            onPageChange?(current)
        }
        if endVisible != endCardVisible {
            endCardVisible = endVisible
            onEndCard?(endVisible)
        }
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
