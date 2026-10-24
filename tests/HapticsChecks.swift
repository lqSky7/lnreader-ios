// HapticsChecks.swift - When scrolling clicks, knocks and thuds, headless.

import Foundation

@main
struct HapticsChecks {

    static func main() {
        checkSpeedometer()
        checkFeel()
        checkDetents()
        checkChapterBreaks()
        checkEdges()
        print("PASS: haptics — speed smoothing and pauses, feel scales with speed, "
            + "steady distance ticks, rate-limited, chapter breaks, edge bumps once per run-in")
    }

    private static func checkSpeedometer() {
        var meter = ScrollSpeedometer()
        precondition(meter.sample(offset: 0, time: 0) == 0, "the first sample has nothing to compare to")
        var speed = 0.0
        for frame in 1...60 { speed = meter.sample(offset: Double(frame) * 10, time: Double(frame) / 60) }
        precondition(abs(speed - 600) < 1, "steady 10 pt per 60 Hz frame settles at 600 pt/s, got \(speed)")
        let jolt = meter.sample(offset: 600 + 100, time: 61.0 / 60)
        precondition(jolt < 6000 * 0.5, "one uneven frame is smoothed, not taken whole")
        let resumed = meter.sample(offset: 750, time: 2)
        precondition(abs(resumed - 50 / (2 - 61.0 / 60)) < 0.001, "after a pause the speed starts over")
        meter.reset()
        precondition(meter.speed == 0 && meter.sample(offset: 9, time: 3) == 0, "reset forgets the last sample")
    }

    private static func checkFeel() {
        precondition(ScrollFeel.level(10) == 0 && ScrollFeel.level(100_000) == 1, "level is clamped")
        let slow = ScrollFeel.detent(speed: 80), fast = ScrollFeel.detent(speed: 3000)
        precondition(fast.intensity > slow.intensity && fast.sharpness > slow.sharpness,
                     "a flick clicks stronger and crisper than a drag")
        let hardest = ScrollFeel.detent(speed: 1e6)
        precondition(hardest.intensity <= 1 && hardest.sharpness <= 1, "values stay in 0...1")
        let wall = ScrollFeel.edge(speed: 3000)
        precondition(wall.sharpness < fast.sharpness, "an edge is duller than a click at the same speed")
        precondition(ScrollFeel.edge(speed: 3000).intensity > ScrollFeel.edge(speed: 80).intensity,
                     "hitting the end harder thuds harder")
    }

    private static func checkDetents() {
        let step = ScrollDetents.spacing
        var detents = ScrollDetents()
        precondition(detents.update(offset: 0, speed: 500, time: 0, userDriven: true) == nil,
                     "the first offset seen is where the reader starts, not a tick")
        precondition(detents.update(offset: step * 0.5, speed: 500, time: 0.1, userDriven: true) == nil,
                     "within one notch: silent")
        precondition(detents.update(offset: step * 1.1, speed: 500, time: 0.2, userDriven: true)?.kind == .detent,
                     "each notch of travel ticks")
        precondition(detents.update(offset: step * 2.1, speed: 500, time: 0.3, userDriven: true) != nil,
                     "and the next one, at the same rhythm")
        precondition(detents.update(offset: step * 1.5, speed: 500, time: 0.4, userDriven: true) != nil,
                     "scrolling back ticks too")
        precondition(detents.update(offset: step * 2.5, speed: 4000, time: 0.405, userDriven: true) == nil,
                     "ticks closer than the engine can separate are dropped")
        precondition(detents.update(offset: step * 3.5, speed: 4000, time: 0.42, userDriven: true) != nil,
                     "and resume once the gap has passed")
        precondition(detents.update(offset: step * 90, speed: 0, time: 1, userDriven: false) == nil,
                     "a jump or auto scroll moves silently")
        precondition(detents.update(offset: step * 90.2, speed: 300, time: 2, userDriven: true) == nil,
                     "and does not tick later for where it jumped to")
        // A steady 600 pt/s drag at 120 Hz ticks once per notch, evenly.
        var steady = ScrollDetents()
        var ticks = 0
        for frame in 0...120 {
            let t = Double(frame) / 120
            if steady.update(offset: 600 * t, speed: 600, time: t, userDriven: true) != nil { ticks += 1 }
        }
        precondition(ticks == Int(600 / step), "one tick per notch over a second's drag, got \(ticks)")
        let slow = ScrollFeel.detent(speed: 80), fast = ScrollFeel.detent(speed: 3000)
        precondition(fast.intensity - slow.intensity < 0.2, "ticks feel even across speeds")
        precondition(slow.sharpness >= 0.7, "even a slow tick is crisp, not mushy")
        detents.reset()
        precondition(detents.update(offset: 0, speed: 300, time: 5, userDriven: true) == nil,
                     "after a reset the next offset is a fresh start")
    }

    private static func checkChapterBreaks() {
        var marks = ScrollChapterMarks()
        precondition(marks.update(row: 6, isChapterBreak: true, speed: 600, userDriven: true) == nil,
                     "opening on a divider is not arriving at one")
        _ = marks.update(row: 7, isChapterBreak: false, speed: 600, userDriven: true)
        precondition(marks.update(row: 7, isChapterBreak: false, speed: 600, userDriven: true) == nil, "pages: nothing")
        let chapter = marks.update(row: 8, isChapterBreak: true, speed: 600, userDriven: true)
        precondition(chapter?.kind == .chapter, "a divider arriving gets the chapter cue")
        precondition(marks.update(row: 8, isChapterBreak: true, speed: 600, userDriven: true) == nil,
                     "once, not every frame the divider stays under the line")
        precondition(marks.update(row: 9, isChapterBreak: false, speed: 600, userDriven: true) == nil,
                     "leaving it is a page again")
        precondition(chapter!.intensity > ScrollFeel.detent(speed: 600).intensity,
                     "a chapter break is felt more than a tick")
        _ = marks.update(row: 3, isChapterBreak: false, speed: 0, userDriven: false)
        precondition(marks.update(row: 4, isChapterBreak: true, speed: 0, userDriven: false) == nil,
                     "a jump onto a divider is silent")
    }

    private static func checkEdges() {
        var bump = ScrollEdgeBump()
        precondition(bump.update(offset: 0, minOffset: 0, maxOffset: 1000, speed: 900, userDriven: true) == nil,
                     "resting exactly at the top is not a hit")
        precondition(bump.update(offset: -12, minOffset: 0, maxOffset: 1000, speed: 900, userDriven: true)?.kind == .edge,
                     "running past the top thuds")
        precondition(bump.update(offset: -30, minOffset: 0, maxOffset: 1000, speed: 600, userDriven: true) == nil,
                     "once per run-in, not every frame of the bounce")
        _ = bump.update(offset: 5, minOffset: 0, maxOffset: 1000, speed: 100, userDriven: true)
        precondition(bump.update(offset: 1010, minOffset: 0, maxOffset: 1000, speed: 1200, userDriven: true) != nil,
                     "after coming back in, the bottom thuds too")
        _ = bump.update(offset: 990, minOffset: 0, maxOffset: 1000, speed: 0, userDriven: true)
        precondition(bump.update(offset: 1003, minOffset: 0, maxOffset: 1000, speed: 10, userDriven: true) == nil,
                     "nudging the end slowly is not a hit")
        var quiet = ScrollEdgeBump()
        precondition(quiet.update(offset: -40, minOffset: 0, maxOffset: 1000, speed: 2000, userDriven: false) == nil,
                     "a programmatic overshoot is silent")
        var short = ScrollEdgeBump()
        precondition(short.update(offset: 0, minOffset: 0, maxOffset: -200, speed: 900, userDriven: true) == nil,
                     "content shorter than the screen: resting at the top is not past the end")
        precondition(short.update(offset: 20, minOffset: 0, maxOffset: -200, speed: 900, userDriven: true) != nil,
                     "and pulling it up is")
    }
}
