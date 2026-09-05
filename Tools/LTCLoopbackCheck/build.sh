#!/bin/bash
# Builds the loopback check tools next to this script.
set -euo pipefail
cd "$(dirname "$0")"
APP=../../MIDITimecode
swiftc -O player.swift -o ltc-player
swiftc -O verifier/main.swift "$APP/Timecode.swift" "$APP/TimecodeMath.swift" "$APP/LTCDecoder.swift" \
    "$APP/HostTime.swift" "$APP/MTCParser.swift" -o mtc-verifier
echo "built ./ltc-player and ./mtc-verifier"
