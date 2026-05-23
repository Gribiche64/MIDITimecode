import CoreMIDI
import Foundation

struct MIDIDevice: Identifiable, Hashable {
    let name: String
    let endpoint: MIDIEndpointRef

    var id: String { "\(name)-\(endpoint)" }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(endpoint)
    }

    static func == (lhs: MIDIDevice, rhs: MIDIDevice) -> Bool {
        lhs.name == rhs.name && lhs.endpoint == rhs.endpoint
    }
}
