# MIDITimecode

A macOS app that displays MIDI Timecode (MTC) with a nixie/valve tube aesthetic. Useful as a timecode reference display during music production, post-production, or live performance.

## Features

- Receives MIDI Timecode (MTC) quarter-frame messages from any connected MIDI source
- Displays HH:MM:SS:FF in a glowing valve tube style
- 6 tube color themes: Blue, Cyan, Green, Orange, Purple, Rainbow
- Optional always-on-top mode (pin toggle in settings bar)
- Resizable window with locked aspect ratio — digits scale to fill
- Hidden title bar, movable by clicking anywhere on the window
- Auto-detects connected MIDI devices with rescan option
- Displays detected frame rate (24, 25, 29.97 DF, 30 fps)

## Requirements

- macOS 14.0+
- Xcode 16.0+
- A MIDI source sending MTC (DAW, hardware transport, etc.)

## Build

Open the project in Xcode:

```bash
open MIDITimecode.xcodeproj
```

Then build and run (Cmd+R).

Or build from the command line:

```bash
xcodebuild -project MIDITimecode.xcodeproj -scheme MIDITimecode -configuration Release build
```

## Usage

1. Launch MIDITimecode
2. Connect a MIDI device that sends MTC (or configure your DAW to output MTC)
3. Select the MIDI source from the dropdown in the settings bar
4. Press play in your DAW — the timecode display updates in real time
5. Change the tube color from the Color dropdown
6. Toggle the pin icon to keep the window always on top
7. Resize the window by dragging any edge — aspect ratio is locked

## Dependencies

None — uses only Apple system frameworks:
- CoreMIDI (MIDI communication)
- SwiftUI (UI)
- Combine (reactive state)
- AppKit (window configuration)
