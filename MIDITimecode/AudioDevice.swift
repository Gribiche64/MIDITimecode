import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Hashable {
    let name: String
    let deviceID: AudioDeviceID
    let inputChannelCount: Int

    var id: String { "\(name)-\(deviceID)" }

    /// Enumerate all audio devices that have input channels.
    static func availableInputDevices() -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize
        )
        guard status == noErr, dataSize > 0 else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize, &deviceIDs
        )
        guard status == noErr else { return [] }

        var devices: [AudioDevice] = []
        for deviceID in deviceIDs {
            let channels = inputChannelCount(for: deviceID)
            guard channels > 0 else { continue }

            let name = deviceName(for: deviceID) ?? "Unknown Device"
            devices.append(AudioDevice(name: name, deviceID: deviceID, inputChannelCount: channels))
        }
        return devices
    }

    // MARK: - Helpers

    private static func deviceName(for deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize = UInt32(MemoryLayout<CFString>.size)
        var result: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &result) { ptr in
            AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, ptr)
        }
        guard status == noErr, let cfName = result?.takeRetainedValue() else { return nil }
        return cfName as String
    }

    private static func inputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return 0 }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferListPointer.deallocate() }

        status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferListPointer)
        guard status == noErr else { return 0 }

        let bufferListPtr = bufferListPointer.assumingMemoryBound(to: AudioBufferList.self)
        let bufferList = bufferListPtr.pointee
        var totalChannels = 0

        // Walk the buffer list using pointer arithmetic
        withUnsafePointer(to: &bufferListPtr.pointee.mBuffers) { firstBufferPtr in
            let buffersPtr = UnsafeRawPointer(firstBufferPtr)
                .assumingMemoryBound(to: AudioBuffer.self)
            for i in 0..<Int(bufferList.mNumberBuffers) {
                totalChannels += Int(buffersPtr[i].mNumberChannels)
            }
        }

        return totalChannels
    }
}
