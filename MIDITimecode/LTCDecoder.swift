import Foundation

/// A decoded LTC frame and where in the audio buffer it completed.
struct DecodedLTCFrame: Equatable {
    let timecode: Timecode
    /// Index (within the buffer passed to `decode`) of the sample at which the
    /// sync word completed, i.e. the last sample of this frame. The next frame
    /// starts one sample later.
    let sampleOffset: Int
}

/// Pure LTC (Linear Timecode / SMPTE) audio decoder.
///
/// Decodes biphase mark encoded audio into timecode frames.
/// Feed audio samples via `processSample(_:)` or `processSamples(_:sampleRate:)`.
/// When a complete 80-bit LTC frame with valid sync word is found, a `Timecode` is returned.
struct LTCDecoder {
    // MARK: - Public state

    /// Last successfully decoded timecode.
    private(set) var lastTimecode: Timecode?

    /// True when reverse sync word detected (tape running backward).
    private(set) var isReversing: Bool = false

    /// True when sync word has been found and decoding is active.
    private(set) var isLocked: Bool = false

    /// Recent peak signal level (0.0–1.0), updated per sample batch.
    private(set) var signalLevel: Float = 0.0

    // MARK: - Configuration

    /// Minimum signal amplitude to register a zero crossing. Relative to recent peak.
    var hysteresisRatio: Float = 0.15

    // MARK: - Internal state

    private var sampleRate: Double = 48000.0

    // Zero-crossing detection (Schmitt trigger)
    private var lastSample: Float = 0.0
    private var sampleCounter: Int = 0
    private var peakLevel: Float = 0.0
    private var schmittHigh: Bool = false  // current polarity state

    // Plausible LTC bit rates: 24 fps × 80 bits = 1920 bit/s up to 30 fps × 80 =
    // 2400 bit/s, with headroom for shuttle speeds. Anything faster is noise.
    private static let maxPlausibleBitRate: Double = 2400.0 * 2.5
    private static let minPlausibleBitRate: Double = 1920.0 / 2.5
    /// Frame durations the timing must fall within to be reported (20 to 36 fps
    /// nominal, plus a little tolerance).
    private static let plausibleFrameDuration: ClosedRange<Double> = (1.0 / 36.0)...(1.0 / 20.0)

    // Bit period tracking
    private var estimatedBitPeriod: Double = 0.0
    private var hasPendingBit: Bool = false
    private var bootstrapCount: Int = 0
    private let bootstrapTarget: Int = 8

    // Resync watchdog — escalating recovery
    private var bitsSinceLastSync: Int = 0
    private let softResyncThreshold: Int = 160   // 2 frames — clear pending bit
    private let hardResyncThreshold: Int = 800   // 10 frames — full reset
    private var softResyncFired: Bool = false

    // Bit buffer — 80 bits stored as two UInt64s
    // New bits are shifted in at the LSB (right). After 80 bits:
    //   bitsHigh[15..0] = LTC bits 0..15 (oldest, reversed: bit 0 at position 15)
    //   bitsLow[63..0]  = LTC bits 16..79 (newest, reversed: bit 79 at position 0)
    // Sync word (LTC bits 64-79) occupies bitsLow[15..0].
    private var bitsLow: UInt64 = 0
    private var bitsHigh: UInt64 = 0
    private var totalBitsReceived: Int = 0

    // Dropout detection
    private var samplesSinceLastCrossing: Int = 0
    private let dropoutThresholdMultiplier: Double = 3.0
    /// True until the first transition after start-up or a dropout. The
    /// interval leading up to that transition is silence, not a bit cell, so
    /// it must not feed the bit-period estimate.
    private var awaitingFirstCrossing: Bool = true

    // Forward sync word: 0011 1111 1111 1101 (SMPTE, MSB-first in temporal order)
    // In our buffer (newest at LSB), this appears as 0x3FFD in bitsLow[15..0].
    private static let syncWordForward: UInt16 = 0x3FFD
    // Reverse sync word (bit-reversed temporal order)
    private static let syncWordReverse: UInt16 = 0xBFFC

    // MARK: - Processing

    /// Process a buffer of audio samples. Returns decoded timecodes (typically 0 or 1 per call).
    mutating func processSamples(_ samples: UnsafeBufferPointer<Float>, sampleRate: Double) -> [Timecode] {
        decode(samples, sampleRate: sampleRate).map(\.timecode)
    }

    /// Process a buffer of audio samples. Returns each decoded frame together
    /// with the buffer offset of the sample that completed it.
    mutating func decode(_ samples: UnsafeBufferPointer<Float>, sampleRate: Double) -> [DecodedLTCFrame] {
        self.sampleRate = sampleRate
        var results: [DecodedLTCFrame] = []

        // Track peak level for this buffer
        var bufferPeak: Float = 0.0
        for i in 0..<samples.count {
            let abs = Swift.abs(samples[i])
            if abs > bufferPeak { bufferPeak = abs }
        }
        // Exponential decay on peak
        peakLevel = max(bufferPeak, peakLevel * 0.995)
        signalLevel = peakLevel

        for i in 0..<samples.count {
            if let tc = processSample(samples[i]) {
                results.append(DecodedLTCFrame(timecode: tc, sampleOffset: i))
            }
        }
        return results
    }

    /// Process a single audio sample. Returns a `Timecode` when a complete frame is decoded.
    mutating func processSample(_ sample: Float) -> Timecode? {
        sampleCounter += 1
        samplesSinceLastCrossing += 1

        // Dropout detection: no transition for several bit periods means the
        // signal is gone. Re-bootstrap from scratch when it returns rather than
        // shifting stale bits and a stale bit period into the next frames.
        if estimatedBitPeriod > 0 {
            let maxSamples = Int(estimatedBitPeriod * dropoutThresholdMultiplier)
            if samplesSinceLastCrossing > maxSamples {
                handleDropout()
            }
        }

        // Schmitt trigger: track polarity with hysteresis to reject noise around zero.
        // We only flip state when the signal clearly exceeds the opposite threshold.
        let upperThreshold = peakLevel * hysteresisRatio
        let lowerThreshold = -upperThreshold

        guard upperThreshold > 0.001 else {
            return nil  // Signal too weak
        }

        let crossed: Bool
        if !schmittHigh && sample > upperThreshold {
            schmittHigh = true
            crossed = true
        } else if schmittHigh && sample < lowerThreshold {
            schmittHigh = false
            crossed = true
        } else {
            crossed = false
        }

        guard crossed else { return nil }

        // We have a zero crossing
        let interval = samplesSinceLastCrossing
        samplesSinceLastCrossing = 0

        // The first transition after silence only tells us the signal is back.
        if awaitingFirstCrossing {
            awaitingFirstCrossing = false
            return nil
        }

        // Reject crossings faster than half a bit cell at the fastest plausible
        // LTC rate: those are noise, not biphase transitions.
        let minHalfBitSamples = sampleRate / Self.maxPlausibleBitRate / 2.0
        guard Double(interval) >= minHalfBitSamples else { return nil }

        // Bootstrap: collect the first few intervals to find the full bit period.
        // The longest interval in any biphase mark signal is exactly one bit period.
        if bootstrapCount < bootstrapTarget {
            if Double(interval) > estimatedBitPeriod {
                estimatedBitPeriod = Double(interval)
            }
            bootstrapCount += 1
            if bootstrapCount == bootstrapTarget, !isPlausibleBitPeriod(estimatedBitPeriod) {
                // Whatever this is, it is not timecode. Start again.
                estimatedBitPeriod = 0.0
                bootstrapCount = 0
            }
            return nil
        }

        // Self-correct: if an interval is much longer than estimated, our estimate
        // was probably from a half-bit. Reset to this longer interval.
        let ratio = Double(interval) / estimatedBitPeriod
        if ratio > 1.7 {
            if isPlausibleBitPeriod(Double(interval)) {
                estimatedBitPeriod = Double(interval)
            } else {
                handleDropout()
            }
            hasPendingBit = false
            return nil
        }

        // Classify interval as short (half-bit / mid-cell) or long (full bit / cell boundary)
        let isShort = ratio < 0.75

        // Adaptive bit period tracking using long intervals
        if !isShort && ratio > 0.75 && ratio < 1.3 {
            estimatedBitPeriod = estimatedBitPeriod * 0.9 + Double(interval) * 0.1
        }

        // Biphase mark decoding:
        // Two short intervals = bit value 1 (mid-cell transition present)
        // One long interval = bit value 0 (no mid-cell transition)
        var decodedBit: Bool?

        if isShort {
            if hasPendingBit {
                decodedBit = true
                hasPendingBit = false
            } else {
                hasPendingBit = true
            }
        } else {
            hasPendingBit = false
            decodedBit = false
        }

        guard let bit = decodedBit else { return nil }

        // Shift bit into the buffer
        return pushBit(bit)
    }

    // MARK: - Bit buffer

    private mutating func pushBit(_ bit: Bool) -> Timecode? {
        // Shift the 80-bit buffer left by 1, new bit enters at LSB
        bitsHigh = (bitsHigh << 1) | (bitsLow >> 63)
        bitsLow = bitsLow << 1
        if bit { bitsLow |= 1 }
        totalBitsReceived += 1
        bitsSinceLastSync += 1

        // Escalating resync watchdog:
        // - Soft (2 frames): just realign the biphase state machine
        // - Hard (10 frames): full re-bootstrap from current signal
        if !softResyncFired && bitsSinceLastSync > softResyncThreshold {
            hasPendingBit = false
            softResyncFired = true
        }
        if bitsSinceLastSync > hardResyncThreshold {
            hasPendingBit = false
            bitsSinceLastSync = 0
            softResyncFired = false
            bitsLow = 0
            bitsHigh = 0
            totalBitsReceived = 0
            estimatedBitPeriod = 0.0
            bootstrapCount = 0
            isLocked = false
        }

        // Need at least 80 bits before checking sync
        guard totalBitsReceived >= 80 else { return nil }

        // The sync word (LTC bits 64-79) occupies the lowest 16 bits of bitsLow.
        // Once locked, allow 1 bit error to ride through minor slips on real
        // signals. Until then demand an exact match: a tolerant match on noise
        // produces convincing false frames.
        let syncCandidate = UInt16(bitsLow & 0xFFFF)
        let forwardErrors = popcount(syncCandidate ^ Self.syncWordForward)
        let reverseErrors = popcount(syncCandidate ^ Self.syncWordReverse)
        let allowedErrors = isLocked ? 1 : 0

        let reversed: Bool
        if forwardErrors <= allowedErrors {
            reversed = false
        } else if reverseErrors <= allowedErrors {
            reversed = true
        } else {
            return nil
        }

        // A sync match on a frame with impossible field values is noise.
        guard let tc = parseFrame(reversed: reversed) else { return nil }
        isReversing = reversed
        isLocked = true
        bitsSinceLastSync = 0
        softResyncFired = false
        lastTimecode = tc
        return tc
    }

    /// Forget everything about the signal after a dropout so decoding
    /// restarts cleanly when it returns.
    private mutating func handleDropout() {
        isLocked = false
        hasPendingBit = false
        estimatedBitPeriod = 0.0
        bootstrapCount = 0
        bitsLow = 0
        bitsHigh = 0
        totalBitsReceived = 0
        bitsSinceLastSync = 0
        softResyncFired = false
        awaitingFirstCrossing = true
    }

    // MARK: - Frame parsing

    /// Returns nil when any field is outside its legal range.
    private func parseFrame(reversed: Bool) -> Timecode? {
        // Extract the 64 data bits (LTC bits 0-63).
        // In the buffer: bitsHigh holds bits 0-15, bitsLow >> 16 holds bits 16-63.
        // But bit ordering is reversed (bit 0 is at MSB side of the combined value).
        let rawData = (UInt64(bitsHigh) << 48) | (bitsLow >> 16)

        // For forward playback: bits arrived 0,1,...,63 so bit 0 is at position 63.
        // bitReverse64 puts bit 0 at position 0 where the BCD extraction expects it.
        // For reverse playback: bits arrived 63,62,...,0 so bit 0 is already at position 0.
        let data = reversed ? rawData : bitReverse64(rawData)

        // Extract BCD fields from the 64 data bits
        // LTC bit layout (bits 0-63):
        // 0-3:   Frame units (BCD)
        // 4-7:   User bits field 1
        // 8-9:   Frame tens (BCD)
        // 10:    Drop frame flag
        // 11:    Color frame flag
        // 12-15: User bits field 2
        // 16-19: Seconds units (BCD)
        // 20-23: User bits field 3
        // 24-26: Seconds tens (BCD)
        // 27:    Biphase correction bit
        // 28-31: User bits field 4
        // 32-35: Minutes units (BCD)
        // 36-39: User bits field 5
        // 40-42: Minutes tens (BCD)
        // 43:    Binary group flag
        // 44-47: User bits field 6
        // 48-51: Hours units (BCD)
        // 52-55: User bits field 7
        // 56-57: Hours tens (BCD)
        // 58:    Binary group flag
        // 59:    Polarity correction bit
        // 60-63: User bits field 8

        let frameUnits = UInt8(data & 0x0F)
        let frameTens = UInt8((data >> 8) & 0x03)
        let dropFrame = ((data >> 10) & 0x01) == 1
        let secondsUnits = UInt8((data >> 16) & 0x0F)
        let secondsTens = UInt8((data >> 24) & 0x07)
        let minutesUnits = UInt8((data >> 32) & 0x0F)
        let minutesTens = UInt8((data >> 40) & 0x07)
        let hoursUnits = UInt8((data >> 48) & 0x0F)
        let hoursTens = UInt8((data >> 56) & 0x03)

        let totalFrames = frameTens * 10 + frameUnits
        let totalSeconds = secondsTens * 10 + secondsUnits
        let totalMinutes = minutesTens * 10 + minutesUnits
        let totalHours = hoursTens * 10 + hoursUnits

        // Determine frame rate from bit period timing; timing outside any
        // real frame rate means the bits are not timecode.
        guard estimatedBitPeriod > 0 else { return nil }
        let frameDuration = estimatedBitPeriod * 80.0 / sampleRate
        guard Self.plausibleFrameDuration.contains(frameDuration) else { return nil }
        var rate = FrameRate.fromFrameDuration(frameDuration)

        // Override with drop-frame if the flag is set
        if dropFrame {
            rate = .df2997
        }

        guard totalHours <= 23, totalMinutes <= 59, totalSeconds <= 59,
              totalFrames <= rate.maxFrames else {
            return nil
        }

        return Timecode(
            hours: totalHours,
            minutes: totalMinutes,
            seconds: totalSeconds,
            frames: totalFrames,
            rate: rate
        )
    }

    // MARK: - Utilities

    /// True when a bit period (in samples) corresponds to a plausible LTC bit rate.
    private func isPlausibleBitPeriod(_ samples: Double) -> Bool {
        guard samples > 0 else { return false }
        let bitRate = sampleRate / samples
        return bitRate >= Self.minPlausibleBitRate && bitRate <= Self.maxPlausibleBitRate
    }

    /// Count set bits in a UInt16.
    private func popcount(_ value: UInt16) -> Int {
        var v = value
        var count = 0
        while v != 0 {
            count += Int(v & 1)
            v >>= 1
        }
        return count
    }

    /// Reverse all 64 bits.
    private func bitReverse64(_ value: UInt64) -> UInt64 {
        var v = value
        v = ((v >> 1) & 0x5555555555555555) | ((v & 0x5555555555555555) << 1)
        v = ((v >> 2) & 0x3333333333333333) | ((v & 0x3333333333333333) << 2)
        v = ((v >> 4) & 0x0F0F0F0F0F0F0F0F) | ((v & 0x0F0F0F0F0F0F0F0F) << 4)
        v = ((v >> 8) & 0x00FF00FF00FF00FF) | ((v & 0x00FF00FF00FF00FF) << 8)
        v = ((v >> 16) & 0x0000FFFF0000FFFF) | ((v & 0x0000FFFF0000FFFF) << 16)
        v = (v >> 32) | (v << 32)
        return v
    }

    /// Reset decoder state (e.g., when switching audio source).
    mutating func reset() {
        lastTimecode = nil
        isReversing = false
        isLocked = false
        signalLevel = 0.0
        lastSample = 0.0
        sampleCounter = 0
        peakLevel = 0.0
        schmittHigh = false
        estimatedBitPeriod = 0.0
        hasPendingBit = false
        bootstrapCount = 0
        bitsLow = 0
        bitsHigh = 0
        totalBitsReceived = 0
        samplesSinceLastCrossing = 0
        bitsSinceLastSync = 0
        softResyncFired = false
        awaitingFirstCrossing = true
    }
}
