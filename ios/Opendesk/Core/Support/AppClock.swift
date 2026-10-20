import Foundation

/// "Now" for everything the app shows: relative times, SLA clocks, chat
/// waits, snoozes. The device clock, except in a debug demo run, which pins
/// it so the same build draws the same screens (`DemoMode`).
enum AppClock {
    static var now: Date {
        #if DEBUG
        if DemoMode.isOn { return DemoMode.anchor }
        #endif
        return .now
    }

    /// The reading for a `TimelineView` tick.
    static func now(at tick: Date) -> Date {
        #if DEBUG
        if DemoMode.isOn { return DemoMode.anchor }
        #endif
        return tick
    }
}
