# Changelog

## Unreleased

### Fixed
- MTC output no longer restarts the quarter-frame sequence on every decoded
  LTC frame. A free-running generator now emits a continuous stream (4
  quarter-frames per frame, groups advancing by 2 frames) and is disciplined
  by the decoded LTC. This removes the intermittent jumps and stalls seen in
  CuePilot.
- Decoded LTC frames are timestamped from the audio buffer's host time and the
  sample at which the sync word ended, instead of buffer arrival time.
- After a dropout the LTC decoder re-bootstraps its bit period instead of
  carrying stale state, which cuts relock time to about two frames and stops
  it emitting a corrupt frame as the signal returns. Frames with impossible
  field values are rejected.

### Added
- MTC Full Frame message on first lock, re-anchor and relock.
- Configurable freewheel on signal loss (0.5 s to 5 s, default 1 s), then
  stop; generator state shown in the settings bar and menu bar.
- Re-anchors require two consecutive consistent frames.
- MIDI packets are sent from a real-time thread when due and carry exact
  host timestamps.
- `MIDITIMECODE_SOURCE_NAME` environment override for test builds.
- Tests: MTC clock stream shape, drop-frame counting, jitter convergence,
  step response, corrupt-frame rejection, freewheel/stop/relock; decoder sample
  offsets at 25 and 30 fps and dropout recovery.

- A silent spare port, "MIDITimecode (spare)", published ahead of the
  real one so CuePilot's index-based input selection lands on it.
- Port carries manufacturer and model; groups start on even frames at
  24/30/29.97 fps; line noise no longer decodes as timecode.

- Audio device hot-plug: the chosen interface is remembered by name and
  re-bound automatically when it is unplugged and returns, after sleep, or
  after an engine configuration change; a watchdog restarts the engine if
  buffers stop; the status bar shows "No Device" while it is absent.
- Virtual MIDI ports are recreated if the MIDI server drops them.
- One engine per process: SwiftUI could build the app's state object twice
  at launch, briefly creating a duplicate audio tap and MIDI port.

- Minimum window width raised so the settings bar never wraps.

### Changed
- MTC input mode feeds the same generator for pass-through.
- README rewritten to describe LTC to MTC operation.
