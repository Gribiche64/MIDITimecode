# LTC loopback check

Two command-line tools that verify the app's MTC output against a real LTC
signal without trusting the app's own display.

- `ltc-player` plays a WAV to a named output device (a loopback device such as
  BlackHole, whose output feeds its own input).
- `mtc-verifier` connects to the app's virtual MIDI source and, at the same time,
  decodes the LTC from the audio device with the app's own `LTCDecoder`. It
  reports quarter-frame continuity, Full Frames, delivery lateness against the
  packet timestamps, and the difference between each MTC group's value and the
  LTC position at the moment of the group's first message.

## Build

```bash
./build.sh
```

## Run

1. Launch a test build of the app under its own source name so the production
   copy and its receivers are untouched, and point it at the loopback device:

   ```bash
   MIDITIMECODE_SOURCE_NAME="MIDITimecode LTC dev" /path/to/MIDITimecode.app/Contents/MacOS/MIDITimecode \
       -inputMode LTC -audioDeviceName "BlackHole 2ch" -audioChannel 0 -virtualMTCEnabled 1
   ```

   Passing settings as arguments keeps them out of the persisted defaults.

2. Start the verifier for the length of the test, then play the file:

   ```bash
   ./mtc-verifier "MIDITimecode LTC dev" "BlackHole 2ch" 46 &
   ./ltc-player /path/to/ltc_test.wav "BlackHole 2ch"
   ```

A test file with a mute in it exercises freewheel and relock, for example:

```bash
ffmpeg -i source.wav -t 45 -af "pan=mono|c0=c0,volume=enable='between(t,20,20.5)':volume=0,aresample=48000,pan=stereo|c0=c0|c1=c0" -ar 48000 ltc_test.wav
```

Good output: 0 sequence restarts, one Full Frame per lock, offsets of 0.000
frames, and no quarter-frame gaps across a mute shorter than the freewheel time.
