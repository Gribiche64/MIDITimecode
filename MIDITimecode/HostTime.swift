import Foundation

/// Conversions between `mach_absolute_time` ticks and seconds.
///
/// The MTC generator schedules everything on the host clock so that audio
/// buffer timestamps, CoreMIDI packet timestamps and the generator's own
/// timeline share one time base.
enum HostTime {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private static let secondsPerTick: Double =
        Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000.0

    /// Current host time in seconds.
    static func now() -> Double {
        seconds(fromTicks: mach_absolute_time())
    }

    static func seconds(fromTicks ticks: UInt64) -> Double {
        Double(ticks) * secondsPerTick
    }

    static func ticks(fromSeconds seconds: Double) -> UInt64 {
        guard seconds > 0 else { return 0 }
        return UInt64(seconds / secondsPerTick)
    }
}
