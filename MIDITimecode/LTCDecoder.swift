import Foundation

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
    var hysteresisRatio: Float = 0.1

    // MARK: - Internal state

    private var sampleRate: Double = 48000.0

    // Zero-crossing detection
    private var lastSample: Float = 0.0
    private var lastCrossingPosition: Int = 0
    private var sampleCounter: Int = 0
    private var peakLevel: Float = 0.0
    private var peakDecay: Float = 0.0

    // Bit period tracking
    private var estimatedBitPeriod: Double = 0.0
    private var lastTransitionWasShort: Bool = false
    private var pendingBit: Bool = false
    private var hasPendingBit: Bool = false

    // Bit buffer — 80 bits stored as two UInt64s (low holds bits 0-63, high holds bits 64-79)
    private var bitsLow: UInt64 = 0
    private var bitsHigh: UInt64 = 0
    private var totalBitsReceived: Int = 0

    // Dropout detection
    private var samplesSinceLastCrossing: Int = 0
    private let dropoutThresholdMultiplier: Double = 3.0

    // Forward sync word: 0011 1111 1111 1101 (bits 64-79 of an LTC frame)
    private static let syncWordForward: UInt16 = 0x3FFD
    // Reverse sync word (bit-reversed)
    private static let syncWordReverse: UInt16 = 0xBFFC

    // MARK: - Processing

    /// Process a buffer of audio samples. Returns decoded timecodes (typically 0 or 1 per call).
    mutating func processSamples(_ samples: UnsafeBufferPointer<Float>, sampleRate: Double) -> [Timecode] {
        self.sampleRate = sampleRate
        var results: [Timecode] = []

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
                results.append(tc)
            }
        }
        return results
    }

    /// Process a single audio sample. Returns a `Timecode` when a complete frame is decoded.
    mutating func processSample(_ sample: Float) -> Timecode? {
        sampleCounter += 1
        samplesSinceLastCrossing += 1

        // Dropout detection
        if estimatedBitPeriod > 0 {
            let maxSamples = Int(estimatedBitPeriod * dropoutThresholdMultiplier)
            if samplesSinceLastCrossing > maxSamples {
                isLocked = false
            }
        }

        // Zero-crossing detection with hysteresis
        let threshold = peakLevel * hysteresisRatio
        guard threshold > 0.001 else {
            lastSample = sample
            return nil  // Signal too weak
        }

        let crossed: Bool
        if lastSample <= 0 && sample > threshold {
            crossed = true
        } else if lastSample >= 0 && sample < -threshold {
            crossed = true
        } else {
            crossed = false
        }

        lastSample = sample

        guard crossed else { return nil }

        // We have a zero crossing
        let interval = samplesSinceLastCrossing
        samplesSinceLastCrossing = 0

        // First crossing — can't determine interval yet
        guard estimatedBitPeriod > 0 || totalBitsReceived > 0 else {
            lastCrossingPosition = sampleCounter
            // Bootstrap: wait for a few crossings to estimate bit period
            if interval > 2 {
                estimatedBitPeriod = Double(interval)
            }
            return nil
        }

        // Bootstrap bit period from first few transitions
        if estimatedBitPeriod == 0 {
            estimatedBitPeriod = Double(interval)
            return nil
        }

        // Classify interval as short (half-bit / mid-cell) or long (full bit / cell boundary)
        let ratio = Double(interval) / estimatedBitPeriod
        let isShort = ratio < 0.75

        // Adaptive bit period tracking using long intervals
        if !isShort {
            estimatedBitPeriod = estimatedBitPeriod * 0.9 + Double(interval) * 0.1
        }

        // Biphase mark decoding:
        // Two short intervals = bit value 1 (mid-cell transition present)
        // One long interval = bit value 0 (no mid-cell transition)
        var decodedBit: Bool?

        if isShort {
            if hasPendingBit {
                // Second short interval — this completes a '1' bit
                decodedBit = true
                hasPendingBit = false
            } else {
                // First short interval — wait for the second
                hasPendingBit = true
            }
        } else {
            // Long interval — this is a '0' bit
            hasPendingBit = false
            decodedBit = false
        }

        guard let bit = decodedBit else { return nil }

        // Shift bit into the buffer
        return pushBit(bit)
    }

    // MARK: - Bit buffer

    private mutating func pushBit(_ bit: Bool) -> Timecode? {
        // Shift the 80-bit buffer left by 1
        bitsHigh = (bitsHigh << 1) | (bitsLow >> 63)
        bitsLow = bitsLow << 1
        if bit { bitsLow |= 1 }
        totalBitsReceived += 1

        // Need at least 80 bits before checking sync
        guard totalBitsReceived >= 80 else { return nil }

        // Check for sync word in bits 64-79 (the high word, low 16 bits)
        let syncCandidate = UInt16(bitsHigh & 0xFFFF)

        if syncCandidate == Self.syncWordForward {
            isReversing = false
            isLocked = true
            return parseFrame(reversed: false)
        } else if syncCandidate == Self.syncWordReverse {
            isReversing = true
            isLocked = true
            return parseFrame(reversed: true)
        }

        return nil
    }

    // MARK: - Frame parsing

    private mutating func parseFrame(reversed: Bool) -> Timecode {
        // The 64 data bits are in bitsLow (when not reversed)
        var data = bitsLow

        if reversed {
            data = bitReverse64(data)
        }

        // Extract BCD fields from the 64 data bits
        // LTC bit layout (data bits 0-63):
        // 0-3:   Frame units
        // 4-7:   User bits field 1
        // 8-9:   Frame tens
        // 10:    Drop frame flag
        // 11:    Color frame flag
        // 12-15: User bits field 2
        // 16-19: Seconds units
        // 20-23: User bits field 3
        // 24-26: Seconds tens
        // 27:    Biphase correction bit
        // 28-31: User bits field 4
        // 32-35: Minutes units
        // 36-39: User bits field 5
        // 40-42: Minutes tens
        // 43:    Binary group flag
        // 44-47: User bits field 6
        // 48-51: Hours units
        // 52-55: User bits field 7
        // 56-57: Hours tens
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

        // Determine frame rate from bit period timing
        var rate: FrameRate
        if estimatedBitPeriod > 0 {
            let frameDuration = estimatedBitPeriod * 80.0 / sampleRate
            rate = FrameRate.fromFrameDuration(frameDuration)
        } else {
            rate = .fps25
        }

        // Override with drop-frame if the flag is set
        if dropFrame {
            rate = .df2997
        }

        let tc = Timecode(
            hours: totalHours,
            minutes: min(totalMinutes, 59),
            seconds: min(totalSeconds, 59),
            frames: totalFrames,
            rate: rate
        )

        lastTimecode = tc
        return tc
    }

    // MARK: - Utilities

    /// Reverse all 64 bits.
    private func bitReverse64(_ value: UInt64) -> UInt64 {
        var v = value
        // Swap adjacent bits
        v = ((v >> 1) & 0x5555555555555555) | ((v & 0x5555555555555555) << 1)
        // Swap adjacent pairs
        v = ((v >> 2) & 0x3333333333333333) | ((v & 0x3333333333333333) << 2)
        // Swap adjacent nibbles
        v = ((v >> 4) & 0x0F0F0F0F0F0F0F0F) | ((v & 0x0F0F0F0F0F0F0F0F) << 4)
        // Swap adjacent bytes
        v = ((v >> 8) & 0x00FF00FF00FF00FF) | ((v & 0x00FF00FF00FF00FF) << 8)
        // Swap adjacent 16-bit words
        v = ((v >> 16) & 0x0000FFFF0000FFFF) | ((v & 0x0000FFFF0000FFFF) << 16)
        // Swap 32-bit halves
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
        lastCrossingPosition = 0
        sampleCounter = 0
        peakLevel = 0.0
        peakDecay = 0.0
        estimatedBitPeriod = 0.0
        lastTransitionWasShort = false
        pendingBit = false
        hasPendingBit = false
        bitsLow = 0
        bitsHigh = 0
        totalBitsReceived = 0
        samplesSinceLastCrossing = 0
    }
}
