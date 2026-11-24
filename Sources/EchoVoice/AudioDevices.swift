import Foundation
import CoreAudio

public struct AudioDevice: Equatable, Sendable { public var id: AudioDeviceID; public var name: String; public var hasInput: Bool; public var hasOutput: Bool }

public enum AudioDevices {
    static func addr(_ sel: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    public static func all() -> [AudioDevice] {
        var a = addr(kAudioHardwarePropertyDevices); var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.map { AudioDevice(id: $0, name: name($0), hasInput: streams($0, kAudioObjectPropertyScopeInput), hasOutput: streams($0, kAudioObjectPropertyScopeOutput)) }
    }

    static func name(_ id: AudioDeviceID) -> String {
        var a = addr(kAudioObjectPropertyName); var s: CFString = "" as CFString; var size = UInt32(MemoryLayout<CFString>.size)
        let r = withUnsafeMutablePointer(to: &s) { AudioObjectGetPropertyData(id, &a, 0, nil, &size, $0) }
        return r == noErr ? s as String : "?"
    }
    static func streams(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Bool {
        var a = addr(kAudioDevicePropertyStreams, scope: scope); var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr && size > 0
    }

    public static func blackHole() -> AudioDevice? { all().first { $0.name.localizedCaseInsensitiveContains("BlackHole") && $0.hasInput && $0.hasOutput } }

    public static func defaultInput() -> AudioDeviceID? { get(kAudioHardwarePropertyDefaultInputDevice) }
    public static func defaultOutput() -> AudioDeviceID? { get(kAudioHardwarePropertyDefaultOutputDevice) }
    @discardableResult public static func setDefaultInput(_ id: AudioDeviceID) -> Bool { set(kAudioHardwarePropertyDefaultInputDevice, id) }

    private static func get(_ sel: AudioObjectPropertySelector) -> AudioDeviceID? {
        var a = addr(sel); var id = AudioDeviceID(0); var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id) == noErr && id != 0 ? id : nil
    }
    private static func set(_ sel: AudioObjectPropertySelector, _ id: AudioDeviceID) -> Bool {
        var a = addr(sel); var v = id
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &v) == noErr
    }
}

/// F11: routes the call's microphone to BlackHole only while speech is playing, then puts the original mic back
/// (also on app quit).
public final class MicRouter: @unchecked Sendable {
    private var original: AudioDeviceID?
    private let lock = NSLock()
    public init() {}
    public var isRouted: Bool { lock.lock(); defer { lock.unlock() }; return original != nil }

    @discardableResult public func routeToBlackHole() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard original == nil, let bh = AudioDevices.blackHole(), let cur = AudioDevices.defaultInput(), cur != bh.id else { return false }
        original = cur
        return AudioDevices.setDefaultInput(bh.id)
    }
    public func restore() {
        lock.lock(); defer { lock.unlock() }
        if let o = original { AudioDevices.setDefaultInput(o); original = nil }
    }
    deinit { restore() }
}
