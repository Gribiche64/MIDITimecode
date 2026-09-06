# MIDITimecode

A macOS app that turns LTC (audio timecode) from an audio interface into a
virtual MIDI Timecode (MTC) source, and displays the running timecode in a
nixie/valve tube style. In production it is the timecode bridge into CuePilot:
LTC in on an audio input, MTC out on the virtual CoreMIDI source
**"MIDITimecode LTC"**.

It can also run as a plain MTC display, reading quarter-frame messages from any
MIDI source, and in that mode it re-transmits a clean MTC stream on the same
virtual source.

## Features

- **LTC decoder**: biphase-mark decoding of SMPTE/EBU timecode from any audio
  input channel, 24 / 25 / 30 fps and 29.97 drop-frame (from the drop-frame
  flag). Signal level, lock and reverse-play indication.
- **Disciplined MTC generator**: a free-running quarter-frame stream (4 per
  frame, 8-message groups advancing by 2 frames) that is steered by the decoded
  LTC the way a hardware converter works. Decoded frames are timestamped on the
  host clock from the audio buffer time and the sample at which the sync word
  ended, so timing does not depend on when the audio buffer happened to arrive.
  - Errors under one frame are slewed out gradually; larger errors re-anchor
    the stream at the next frame boundary and send an MTC Full Frame so the
    receiver relocates at once.
  - A re-anchor needs two consecutive, consistent frames, so a single corrupt
    decode cannot move the output.
  - On loss of signal the stream freewheels for a configurable time (0.5 s to
    5 s, default 1 s), then stops. Relock sends a Full Frame and resumes.
  - Messages are sent from a real-time thread at the moment they are due,
    stamped with that time, so receivers that ignore timestamps (WebMIDI
    hosts such as CuePilot) still get them on time.
- **MTC input mode** for use as a display, with pass-through to the virtual
  source via the same generator.
- Valve-tube display with six colour themes, always-on-top, resizable with a
  locked aspect ratio, menu bar timecode readout.
- Settings (mode, devices, channel, colour, MTC output, freewheel) persist
  between launches.

## Requirements

- macOS 14.0+
- Xcode 16.0+ to build
- For LTC: an audio input carrying timecode (interface channel, or a loopback
  device such as BlackHole for testing)
- For MTC display mode: a MIDI source sending MTC

## Build

```bash
open MIDITimecode.xcodeproj
```

Then build and run (Cmd+R). From the command line:

```bash
xcodebuild -project MIDITimecode.xcodeproj -scheme MIDITimecode -configuration Release build
```

Run the unit tests:

```bash
xcodebuild test -project MIDITimecode.xcodeproj -scheme MIDITimecode -destination 'platform=macOS'
```

If a copy of the app is already running (the installed one, for instance),
the test host shares its bundle identifier and the test runner can hang
"before establishing connection". Give the test build its own identifier:

```bash
xcodebuild test -project MIDITimecode.xcodeproj -scheme MIDITimecode -destination 'platform=macOS' 'PRODUCT_BUNDLE_IDENTIFIER=Rob-Sinclair-Inc.$(TARGET_NAME).dev'
```

## Usage: LTC in, MTC out

1. Launch MIDITimecode and pick **LTC** in the mode menu.
2. Choose the audio device and the channel carrying timecode.
3. Turn on **MTC Out**. The label reads Off (dim), Waiting (white, port up,
   no timecode yet), Locked (orange) or Freewheel (yellow, signal lost).
   Click and hold (or right-click) the label to set the freewheel time.
4. In the receiving application, select the MIDI source
   **"MIDITimecode LTC"** as its MTC input. In CuePilot: Setup → Timecode,
   source MTC, device "MIDITimecode LTC".

## Usage: MTC display

1. Pick **MTC** in the mode menu and choose the MIDI source.
2. Press play in the sending application; the display follows.

## CuePilot note

CuePilot 8.5.2 binds its MIDI input by a saved list index and, with no
device name stored, reads index 1 as the *second* port in the list. With
one port present it binds nothing and its MIDI indicator flickers. The app
therefore publishes a silent spare port, "MIDITimecode (spare)", just before
the real one, so "MIDITimecode LTC" is always second. Both ports keep fixed
IDs across launches. Quit any other virtual MIDI source (Lockstep, for
example) before starting CuePilot, since a port bound once is remembered by
name until CuePilot restarts.

## Frame rates

The frame rate is measured from the LTC bit period, and the drop-frame flag
selects 29.97 DF. 30 fps and 29.97 fps non-drop have the same bit pattern and
cannot be told apart from LTC alone; both are reported and sent as 30 fps,
which is what the rate code in MTC expects for either.

## Testing against a real signal

A test build can publish under a different source name so it can run beside
the production copy without receivers picking it up:

```bash
MIDITIMECODE_SOURCE_NAME="MIDITimecode LTC dev" /path/to/MIDITimecode.app/Contents/MacOS/MIDITimecode
```

Play an LTC file into a loopback device (for example BlackHole) and read the
MTC with a second receiver. `Tools/LTCLoopbackCheck/` contains an independent
reader that decodes the LTC itself and measures the MTC against it; see its
README.

## Project layout

- `LTCDecoder.swift`: pure biphase-mark decoder; reports each frame with the
  buffer offset of its last sample.
- `AudioManager.swift`: audio input tap; timestamps decoded frames on the host
  clock.
- `MTCClock.swift`: pure model of the disciplined quarter-frame stream.
- `MTCStreamScheduler.swift`: real-time thread that runs the clock and hands
  timestamped messages to CoreMIDI.
- `VirtualMIDISource.swift`: the virtual CoreMIDI source.
- `TimecodeMath.swift`: frame-index arithmetic including drop-frame.
- `MTCGenerator.swift`, `MTCParser.swift`: MTC byte formats.
- `TimecodeEngine.swift`: wires inputs, generator, settings and UI.
- `MIDITimecodeTests/`: XCTest suite for the decoder, timecode math, the
  clock model and the MTC formats.

## Dependencies

None beyond Apple frameworks: AVFoundation and CoreAudio (audio input),
CoreMIDI, SwiftUI, Combine, AppKit.
