// MangaReaderControls.swift - The decisions behind the manga reader's inputs.
//
// Pure on purpose: where a tap lands, how fast a hold scrolls, whether a volume
// change was a button press. The UIKit pieces (`WebtoonScrollController`,
// `VolumeKeyHost`) only feed these functions and act on the answer, so the
// rules can be checked headless.

import CoreGraphics
import Foundation

// MARK: - Tap zones

/// What a tap should do.
enum MangaTapAction: Equatable {
    case previous
    case next
    case menu
}

/// How the screen is divided into tap targets in paged mode.
///
/// Layouts are described for left-to-right reading. A right-to-left series (or
/// the invert toggle) swaps previous and next; the menu zone never moves.
enum MangaTapZoneLayout: String, Codable, CaseIterable, Identifiable {
    /// Left third previous, right third next, middle opens the menu.
    case standard
    /// Top and left previous, bottom and right next, centre opens the menu.
    case lShaped
    /// Left third previous, everything else next, a strip along the top opens the menu.
    case kindlish
    /// Narrow strips on the left and right edges turn pages, the rest is the menu.
    case edge
    /// Taps never turn pages; any tap toggles the menu.
    case disabled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: "Default"
        case .lShaped: "L-shaped"
        case .kindlish: "Kindle-style"
        case .edge: "Edges"
        case .disabled: "Disabled"
        }
    }

    var summary: String {
        switch self {
        case .standard: "Left and right thirds turn the page"
        case .lShaped: "Top and left go back, bottom and right go forward"
        case .kindlish: "Left third goes back, the rest goes forward"
        case .edge: "Only the screen edges turn the page"
        case .disabled: "Taps only show or hide the controls"
        }
    }

    /// The action for a tap at `point` in a reader of `size`.
    func action(
        at point: CGPoint,
        in size: CGSize,
        inverted: Bool = false,
        rightToLeft: Bool = false
    ) -> MangaTapAction {
        guard size.width > 0, size.height > 0 else { return .menu }
        let x = point.x / size.width
        let y = point.y / size.height

        let base: MangaTapAction
        switch self {
        case .standard:
            base = x < 1.0 / 3 ? .previous : (x > 2.0 / 3 ? .next : .menu)
        case .lShaped:
            if y < 1.0 / 3 || x < 1.0 / 3 {
                base = .previous
            } else if x > 2.0 / 3 || y > 2.0 / 3 {
                base = .next
            } else {
                base = .menu
            }
        case .kindlish:
            if y < 0.12 { base = .menu } else { base = x < 1.0 / 3 ? .previous : .next }
        case .edge:
            base = x < 0.2 ? .previous : (x > 0.8 ? .next : .menu)
        case .disabled:
            return .menu
        }

        // Two reversals cancel: an inverted layout on a right-to-left series
        // is the left-to-right layout again.
        guard inverted != rightToLeft else { return base }
        switch base {
        case .previous: return .next
        case .next: return .previous
        case .menu: return .menu
        }
    }
}

// MARK: - Scrolling

/// Hold-to-scroll: the press speed, and how a vertical drag while holding
/// changes it.
struct HoldScrollConfig: Codable, Equatable {
    /// Points per second when the hold starts.
    var baseSpeed: Double = 180
    /// Points per second gained for each point the finger moves.
    var speedPerPoint: Double = 2
    var minSpeed: Double = 40
    var maxSpeed: Double = 1500
    /// `true`: dragging up speeds the scroll up and dragging down slows it.
    /// `false`: the other way round.
    var upIncreases: Bool = true
    /// Tick as the speed changes while holding, and a firmer tap at the limits.
    var haptics: Bool = true

    init() {}

    /// Missing keys keep their defaults, so adding a setting later does not
    /// discard what was saved before it existed.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = HoldScrollConfig()
        baseSpeed = try c.decodeIfPresent(Double.self, forKey: .baseSpeed) ?? d.baseSpeed
        speedPerPoint = try c.decodeIfPresent(Double.self, forKey: .speedPerPoint) ?? d.speedPerPoint
        minSpeed = try c.decodeIfPresent(Double.self, forKey: .minSpeed) ?? d.minSpeed
        maxSpeed = try c.decodeIfPresent(Double.self, forKey: .maxSpeed) ?? d.maxSpeed
        upIncreases = try c.decodeIfPresent(Bool.self, forKey: .upIncreases) ?? d.upIncreases
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? d.haptics
    }

    static let baseRange = 20.0...1200.0
    static let stepRange = 0.5...6.0

    /// Speed after the finger has moved `dragY` points from where the hold began.
    /// Positive `dragY` is downwards, as in screen coordinates.
    func speed(forDrag dragY: Double) -> Double {
        let toward = upIncreases ? -dragY : dragY
        return min(max(baseSpeed + toward * speedPerPoint, lower), upper)
    }

    /// Bounds with a sane order even if the saved values were not.
    var lower: Double { max(1, min(minSpeed, maxSpeed)) }
    var upper: Double { max(lower, maxSpeed) }
}

/// What the hold-to-scroll haptics should do for a speed change.
enum HoldHaptic: Equatable {
    /// The speed crossed a step: a light selection tick.
    case tick
    /// The speed hit its minimum or maximum: a firmer tap.
    case limit
}

/// Decides when a changing hold speed deserves a haptic: one tick per
/// `step` points per second crossed, and one firmer tap on arriving at either
/// limit. Not every frame — a drag changes the speed continuously, and a
/// buzz per frame is noise.
struct HoldHapticTracker {
    static let step = 40.0

    private var bucket: Int
    private var atLimit: Bool

    init(startSpeed: Double, config: HoldScrollConfig) {
        bucket = Int((startSpeed / Self.step).rounded(.down))
        atLimit = startSpeed <= config.lower || startSpeed >= config.upper
    }

    mutating func update(speed: Double, config: HoldScrollConfig) -> HoldHaptic? {
        let limited = speed <= config.lower || speed >= config.upper
        defer { atLimit = limited }
        let next = Int((speed / Self.step).rounded(.down))
        if limited, !atLimit {
            bucket = next
            return .limit
        }
        guard next != bucket else { return nil }
        bucket = next
        // Sliding along a limit crosses no new step worth a tick.
        return limited ? nil : .tick
    }
}

enum ScrollStep {

    /// Longest frame gap that counts as continuous motion. After a stall (the
    /// app was suspended, a sheet was up) a raw gap would jump the page.
    static let maxFrameGap = 0.1

    /// Advance `offset` by `speed` points per second over `dt` seconds, never
    /// past `maxOffset`. `reachedEnd` is true on the step that arrives there.
    static func advance(
        offset: Double,
        speed: Double,
        dt: Double,
        maxOffset: Double
    ) -> (offset: Double, reachedEnd: Bool) {
        guard speed > 0, dt > 0 else { return (offset, offset >= maxOffset) }
        let next = offset + speed * min(dt, maxFrameGap)
        if next >= maxOffset { return (max(maxOffset, min(offset, maxOffset)), true) }
        return (next, false)
    }
}

// MARK: - Volume keys

enum VolumeKey: Equatable {
    case up
    case down
}

/// Tells a volume button press from the app resetting the volume itself.
///
/// iOS reports a button press only as a new `outputVolume`. To keep a press
/// observable at the ends of the range the reader parks the volume at `target`
/// and sets it back after every press; that reset is reported too, and must not
/// be read as another press.
struct VolumeKeyDetector {
    let target: Float
    private(set) var last: Float
    private let tolerance: Float = 0.001

    init(target: Float = 0.5, last: Float? = nil) {
        self.target = target
        self.last = last ?? target
    }

    /// Feed each reported volume; returns the button pressed, if any.
    mutating func consume(_ volume: Float) -> VolumeKey? {
        defer { last = volume }
        if abs(volume - target) < tolerance { return nil }
        if volume > last + tolerance { return .up }
        if volume < last - tolerance { return .down }
        return nil
    }
}

// MARK: - Stored control settings

/// Reader input settings that follow the user rather than the series.
///
/// One JSON value under one `@AppStorage` key, so the reader observes a single
/// property instead of one per knob.
struct MangaControlSettings: Equatable {
    var volumeKeys = false
    /// `false`: volume up goes back, volume down goes forward.
    var volumeKeysInverted = false
    /// Points per second for auto scroll.
    var autoScrollSpeed: Double = 60
    var hold = HoldScrollConfig()
    var holdScrollEnabled = true

    static let autoSpeedRange = 10.0...600.0

    static let storageKey = "manga.controls"

    init() {}

    /// Volume up goes back unless inverted.
    func isForward(_ key: VolumeKey) -> Bool {
        (key == .down) != volumeKeysInverted
    }

    /// The stored shape. Every field optional, so a value saved before a
    /// setting existed still loads and the new setting keeps its default.
    ///
    /// Deliberately not `MangaControlSettings: Codable`: a `RawRepresentable`
    /// that is also `Codable` encodes through `rawValue`, which encodes the
    /// value, which calls `rawValue`...
    private struct Payload: Codable {
        var volumeKeys: Bool?
        var volumeKeysInverted: Bool?
        var autoScrollSpeed: Double?
        var hold: HoldScrollConfig?
        var holdScrollEnabled: Bool?
    }
}

extension MangaControlSettings: RawRepresentable {
    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return nil }
        let defaults = MangaControlSettings()
        volumeKeys = payload.volumeKeys ?? defaults.volumeKeys
        volumeKeysInverted = payload.volumeKeysInverted ?? defaults.volumeKeysInverted
        autoScrollSpeed = payload.autoScrollSpeed ?? defaults.autoScrollSpeed
        hold = payload.hold ?? defaults.hold
        holdScrollEnabled = payload.holdScrollEnabled ?? defaults.holdScrollEnabled
    }

    var rawValue: String {
        let payload = Payload(
            volumeKeys: volumeKeys,
            volumeKeysInverted: volumeKeysInverted,
            autoScrollSpeed: autoScrollSpeed,
            hold: hold,
            holdScrollEnabled: holdScrollEnabled
        )
        guard let data = try? JSONEncoder().encode(payload),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }
}
