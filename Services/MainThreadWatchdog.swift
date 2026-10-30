// MainThreadWatchdog.swift - Debug builds: say what blocked the main thread.
//
// Stalls in this app have been found one at a time, by a device trace after
// someone felt the lag: a save per scroll tick, a relationship count per row,
// a free-space query per downloaded page. This names the next one as it
// happens. A background thread pings the main queue; when main has not answered
// within `threshold`, it suspends main for a moment, walks its stack, and logs
// the symbols under the `hang` category once main answers (Xcode console, or
// Console.app filtered to subsystem `com.lnreader`).
//
// Debug only: Release and profiling builds never include it.

#if DEBUG
import Darwin
import Foundation
import os

final class MainThreadWatchdog: @unchecked Sendable {
    static let shared = MainThreadWatchdog()

    /// Longer than this unanswered is logged: past three frames at 120 Hz.
    private let threshold: DispatchTimeInterval = .milliseconds(40)
    /// Pause between pings, so the watchdog itself costs nothing measurable.
    private let interval: TimeInterval = 0.05
    private static let maxFrames = 48

    private let logger = Logger(subsystem: "com.lnreader", category: "hang")
    private var mainThread: thread_act_t = 0
    /// Main's stack, `[stackBottom, stackTop)`; the frame walk never reads outside it.
    private var stackTop: UInt = 0
    private var stackBottom: UInt = 0
    private var started = false
    /// Filled while main is suspended, so it is allocated up front: allocating
    /// with main stopped can deadlock on a lock main was holding.
    private let frames = UnsafeMutablePointer<UInt>.allocate(capacity: MainThreadWatchdog.maxFrames)

    private init() {}

    /// Call once, on the main thread.
    func start() {
        guard Thread.isMainThread, !started else { return }
        started = true
        mainThread = mach_thread_self()
        let main = pthread_self()
        stackTop = UInt(bitPattern: pthread_get_stackaddr_np(main))
        stackBottom = stackTop - UInt(pthread_get_stacksize_np(main))
        let thread = Thread { [self] in watch() }
        thread.name = "MainThreadWatchdog"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    private func watch() {
        while true {
            let answered = DispatchSemaphore(value: 0)
            let sent = DispatchTime.now()
            DispatchQueue.main.async { answered.signal() }
            if answered.wait(timeout: sent + threshold) == .timedOut {
                let count = sampleMain()
                answered.wait()
                let blocked = Double(DispatchTime.now().uptimeNanoseconds - sent.uptimeNanoseconds) / 1_000_000
                let stack = symbolicate(count)
                logger.warning("Main thread blocked \(Int(blocked)) ms\n\(stack, privacy: .public)")
            }
            Thread.sleep(forTimeInterval: interval)
        }
    }

    /// Return addresses of the main thread's stack, newest first, into `frames`.
    /// Reads only memory inside main's own stack, and allocates nothing while
    /// main is suspended.
    private func sampleMain() -> Int {
        #if arch(arm64)
        guard stackTop > stackBottom, thread_suspend(mainThread) == KERN_SUCCESS else { return 0 }
        defer { thread_resume(mainThread) }

        var state = arm_thread_state64_t()
        var stateCount = mach_msg_type_number_t(
            MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &state) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(stateCount)) {
                thread_get_state(mainThread, ARM_THREAD_STATE64, $0, &stateCount)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        var count = 0
        frames[count] = Self.strip(UInt(state.__pc)); count += 1
        frames[count] = Self.strip(UInt(state.__lr)); count += 1
        var fp = UInt(state.__fp)
        // Each frame record is [previous fp, return address], 16 bytes, on main's stack.
        while count < Self.maxFrames, fp % 8 == 0, fp >= stackBottom, fp + 16 <= stackTop {
            guard let record = UnsafePointer<UInt>(bitPattern: fp) else { break }
            let next = record[0]
            let returnAddress = Self.strip(record[1])
            guard returnAddress != 0 else { break }
            frames[count] = returnAddress; count += 1
            guard next > fp else { break }
            fp = next
        }
        return count
        #else
        return 0
        #endif
    }

    /// Drop pointer-authentication bits from a return address signed by an
    /// arm64e system framework.
    private static func strip(_ address: UInt) -> UInt { address & 0x0000_000F_FFFF_FFFF }

    private func symbolicate(_ count: Int) -> String {
        guard count > 0 else { return "  (no stack)" }
        return (0..<count).map { index -> String in
            let address = frames[index]
            var info = Dl_info()
            guard dladdr(UnsafeRawPointer(bitPattern: address), &info) != 0 else {
                return String(format: "  %2d  0x%lx", index, address)
            }
            let image = info.dli_fname.map { URL(fileURLWithPath: String(cString: $0)).lastPathComponent } ?? "?"
            let symbol = info.dli_sname.map { Self.demangle(String(cString: $0)) } ?? "?"
            return String(format: "  %2d  %@  %@", index, image, symbol)
        }.joined(separator: "\n")
    }

    private static func demangle(_ name: String) -> String {
        guard let demangled = name.withCString({ swiftDemangle($0, strlen($0), nil, nil, 0) }) else { return name }
        defer { free(demangled) }
        return String(cString: demangled)
    }
}

@_silgen_name("swift_demangle")
private func swiftDemangle(
    _ mangledName: UnsafePointer<CChar>?,
    _ mangledNameLength: Int,
    _ outputBuffer: UnsafeMutablePointer<CChar>?,
    _ outputBufferSize: UnsafeMutablePointer<Int>?,
    _ flags: UInt32
) -> UnsafeMutablePointer<CChar>?
#endif
