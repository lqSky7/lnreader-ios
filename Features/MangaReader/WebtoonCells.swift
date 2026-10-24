// WebtoonCells.swift - The cells of the webtoon strip.

import SwiftUI
import UIKit

/// One page. Owns its own load, so a slow page never blocks its neighbours, and
/// gives its bitmap back when it is reused.
final class WebtoonPageCell: UICollectionViewCell {
    static let reuseID = "page"

    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let failure = UIStackView()
    private let failureLabel = UILabel()
    private var task: Task<Void, Never>?
    private var retry: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .black
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.frame = contentView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(imageView)

        spinner.color = .white
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(spinner)

        failureLabel.font = .preferredFont(forTextStyle: .footnote)
        failureLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        var config = UIButton.Configuration.bordered()
        config.title = "Retry"
        config.baseForegroundColor = .white
        let button = UIButton(configuration: config)
        button.addAction(UIAction { [weak self] _ in self?.retry?() }, for: .touchUpInside)
        failure.axis = .vertical
        failure.spacing = 14
        failure.alignment = .center
        failure.addArrangedSubview(failureLabel)
        failure.addArrangedSubview(button)
        failure.isHidden = true
        failure.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(failure)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            failure.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            failure.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        task?.cancel()
        task = nil
        imageView.image = nil
        failure.isHidden = true
        spinner.stopAnimating()
    }

    @MainActor
    func show(page: SourcePage, sourceKey: String, loader: PageLoader, targetWidth: CGFloat, scale: CGFloat) {
        task?.cancel()
        failure.isHidden = true
        retry = { [weak self] in
            self?.show(page: page, sourceKey: sourceKey, loader: loader, targetWidth: targetWidth, scale: scale)
        }

        if let cached = PageImageCache.shared.object(forKey: page.url as NSString) {
            imageView.image = cached
            spinner.stopAnimating()
            return
        }
        imageView.image = nil
        spinner.startAnimating()

        task = Task { @MainActor [weak self] in
            do {
                let data = try await loader.image(for: page, sourceKey: sourceKey)
                guard !Task.isCancelled else { return }
                // The slot learns its real height before the decode finishes.
                PageImageCache.noteRatio(from: data, forKey: page.url)
                let decoded = await PageDecode.decode(data, targetWidth: targetWidth, screenScale: scale)
                guard !Task.isCancelled else { return }
                guard let decoded else {
                    throw HTTPError.transport("Page \(page.index + 1) is not a valid image")
                }
                PageImageCache.store(decoded, forKey: page.url)
                self?.imageView.image = decoded
                self?.spinner.stopAnimating()
            } catch {
                guard !Task.isCancelled else { return }
                self?.failureLabel.text = "Page \(page.index + 1) could not be loaded"
                self?.failure.isHidden = false
                self?.spinner.stopAnimating()
            }
        }
    }
}

/// The divider between two stitched chapters.
final class WebtoonEndCell: UICollectionViewCell {
    static let reuseID = "end"

    func show(title: String, loading: Bool) {
        backgroundColor = .black
        contentConfiguration = UIHostingConfiguration {
            ChapterDivider(title: title, loading: loading)
        }
        .margins(.all, 0)
    }
}

/// A black box with the next chapter's title, between the last page of one
/// chapter and the first of the next.
private struct ChapterDivider: View {
    let title: String
    let loading: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text("Next chapter")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.5))
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            if loading {
                ProgressView().tint(.white).padding(.top, 6)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .accessibilityElement(children: .combine)
    }
}
