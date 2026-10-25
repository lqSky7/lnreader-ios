// ScrollHaptics.swift - When scrolling deserves a haptic, and how it should feel.
//
// Pure on purpose, like MangaReaderControls.swift: the readers feed in offsets,
// times and the row under the reading line, and `Haptics` plays what comes
// back. The rules can then be checked headless (tests/HapticsChecks.swift).
//
// The feel being aimed at is a soft swell every few points of travel, after
// the login button's rising haptic in Traverse: round rather than crisp,
// rising as you read on and falling as you scroll back, and stronger the
// faster the scroll. Ticks are capped at the fastest rate the Taptic Engine
// can separate. Chapter breaks get a cue of their own, and running into either
// end of the content lands with a thud as heavy as the scroll that hit it.

import Foundation

/// Which way the content is moving. `forward` is reading on (the offset grows);
/// `backward` is scrolling back up.
enum ScrollDirection: Equatable {
    case forward
    case backward
}

/// One haptic a scroll wants. Intensity and sharpness are Core Haptics values, 0...1.
struct ScrollCue: Equatable {
    enum Kind: Equatable {
        /// A page seam passed the reading line.
        case detent
        /// A chapter divider reached the reading line.
        case chapter
        /// The scroll ran past the top or the bottom of the content.
        case edge
    }

    var kind: Kind
    var intensity: Double
    var sharpness: Double
    var direction: ScrollDirection = .forward
}

// MARK: - Speed

/// Scroll speed from successive offsets, smoothed so one uneven frame does not
/// make one click louder than its neighbours.
struct ScrollSpeedometer {
    /// Time constant of the smoothing, in seconds. Expressed in time rather than
    /// samples so a 120 Hz screen and a 60 Hz one feel the same.
    static let smoothing = 0.05
    /// A gap longer than this is a pause, not motion: the next sample starts over.
    static let pause = 0.25

    /// Points per second, unsigned.
    private(set) var speed: Double = 0
    private var last: (offset: Double, time: Double)?

    @discardableResult
    mutating func sample(offset: Double, time: Double) -> Double {
        defer { last = (offset, time) }
        guard let last, time > last.time else { return speed }
        let dt = time - last.time
        let instant = abs(offset - last.offset) / dt
        if dt > Self.pause {
            speed = instant
        } else {
            speed += (instant - speed) * (1 - exp(-dt / Self.smoothing))
        }
        return speed
    }

    mutating func reset() {
        speed = 0
        last = nil
    }
}

// MARK: - Feel

enum ScrollFeel {
    /// Speeds below this all feel like the slowest drag; above `fast`, like the hardest flick.
    static let slow = 60.0
    static let fast = 4000.0

    /// Where `speed` sits between `slow` and `fast`, on a log scale: the
    /// difference between 100 and 200 pt/s is felt as much as 2000 and 4000.
    static func level(_ speed: Double) -> Double {
        let low = log(slow), high = log(fast)
        return min(max((log(max(speed, 1)) - low) / (high - low), 0), 1)
    }

    /// Soft and swelling, not a hard click: sharpness stays low at every speed,
    /// while intensity climbs steeply with speed so a flick is unmistakably
    /// stronger than a drag. `direction` only chooses the envelope's shape.
    static func detent(speed: Double, direction: ScrollDirection = .forward) -> ScrollCue {
        let t = level(speed)
        return ScrollCue(
            kind: .detent,
            intensity: 0.30 + 0.55 * t,
            sharpness: 0.28 + 0.34 * t,
            direction: direction
        )
    }

    static func edge(speed: Double) -> ScrollCue {
        let t = level(speed)
        // Dull on purpose: an end is a wall, not a click.
        return ScrollCue(kind: .edge, intensity: 0.42 + 0.58 * t, sharpness: 0.12 + 0.33 * t)
    }

    static func chapter(speed: Double) -> ScrollCue {
        let t = level(speed)
        return ScrollCue(kind: .chapter, intensity: 0.7 + 0.3 * t, sharpness: 0.45 + 0.3 * t)
    }
}

// MARK: - Detents

/// A steady tick for every `spacing` points scrolled, like a ratchet: the same
/// rhythm whatever is on screen, so the scroll is felt the whole way rather
/// than once per page. Only a scroll the reader is driving (a drag or its
/// momentum) ticks; a jump, a restore or auto scroll moves silently.
struct ScrollDetents {
    /// Points of travel per tick.
    static let spacing = 28.0
    /// The Taptic Engine cannot separate clicks closer than this; a flick faster
    /// than `spacing / minimumGap` ticks at this rate instead, a steady fast purr.
    static let minimumGap = 0.014

    private var notch: Int?
    private var lastClick = -Double.infinity

    mutating func update(offset: Double, speed: Double, time: Double, userDriven: Bool) -> ScrollCue? {
        let current = Int((offset / Self.spacing).rounded(.down))
        defer { notch = current }
        guard let notch, notch != current, userDriven else { return nil }
        guard time - lastClick >= Self.minimumGap else { return nil }
        lastClick = time
        // Offset growing means reading on; shrinking means scrolling back.
        return ScrollFeel.detent(speed: speed, direction: current > notch ? .forward : .backward)
    }

    /// Forget the position, so a rebuilt list does not tick for the jump.
    mutating func reset() {
        notch = nil
    }
}

/// Fires once as a chapter divider arrives under the reading line.
struct ScrollChapterMarks {
    private var row: Int?

    /// - Parameters:
    ///   - row: The row under the reading line, `nil` if none is.
    ///   - isChapterBreak: That row is a chapter divider.
    mutating func update(row: Int?, isChapterBreak: Bool, speed: Double, userDriven: Bool) -> ScrollCue? {
        guard let row else { return nil }
        defer { self.row = row }
        guard let previous = self.row, previous != row, isChapterBreak, userDriven else { return nil }
        return ScrollFeel.chapter(speed: speed)
    }
}

// MARK: - Edges

/// Fires once as a scroll runs past either end of the content into the bounce.
struct ScrollEdgeBump {
    /// Slower than this is a reader nudging the end, not hitting it.
    static let minimumSpeed = 25.0
    /// Rounding slack, in points.
    static let slack = 0.5

    private var beyond = false

    mutating func update(
        offset: Double,
        minOffset: Double,
        maxOffset: Double,
        speed: Double,
        userDriven: Bool
    ) -> ScrollCue? {
        let upper = max(minOffset, maxOffset)
        let isBeyond = offset < minOffset - Self.slack || offset > upper + Self.slack
        defer { beyond = isBeyond }
        guard isBeyond, !beyond, userDriven, speed >= Self.minimumSpeed else { return nil }
        return ScrollFeel.edge(speed: speed)
    }
}
