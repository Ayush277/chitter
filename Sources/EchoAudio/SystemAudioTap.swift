import AVFoundation
import CoreAudio

public enum AudioTapError: Error, CustomStringConvertible {
    case osStatus(String, OSStatus), noFormat
    public var description: String {
        switch self {
        case .osStatus(let w, let s): return "\(w) failed (OSStatus \(s)). Allow “System Audio Recording” for Chitter in System Settings → Privacy & Security."
        case .noFormat: return "Could not read the tap's audio format."
        }
    }
}

/// Captures everything the Mac plays using a Core Audio process tap (macOS 14.4+), excluding Chitter's own process
/// so interpreted speech is never re-transcribed. No Screen Recording permission needed.
public final class SystemAudioTap: @unchecked Sendable {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let resampler = AudioResampler()
    private let queue = DispatchQueue(label: "chitter.tap", qos: .userInitiated)
    public private(set) var isRunning = false

    public init() {}

    public static func processObject(forPID pid: pid_t) -> AudioObjectID? {
        var pid = pid
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var obj = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let st = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr,
                                            UInt32(MemoryLayout<pid_t>.size), &pid, &size, &obj)
        return st == noErr && obj != kAudioObjectUnknown ? obj : nil
    }

    /// Uses the SDK's own constants: a mistyped key is silently ignored by Core Audio and yields no audio at all.
    static func tapList(uuid: String) -> [[String: Any]] { [[kAudioSubTapUIDKey: uuid, kAudioSubTapDriftCompensationKey: true]] }

    /// `onSamples` receives 16 kHz mono Float32 chunks on a background queue.
    public func start(onSamples: @escaping @Sendable ([Float]) -> Void) throws {
        guard !isRunning else { return }
        var exclude: [AudioObjectID] = []
        if let me = Self.processObject(forPID: getpid()) { exclude.append(me) }
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: exclude)
        desc.name = "Chitter tap"
        desc.uuid = UUID()
        desc.muteBehavior = .unmuted
        desc.isPrivate = true

        var st = AudioHardwareCreateProcessTap(desc, &tapID)
        guard st == noErr else { throw AudioTapError.osStatus("Creating the audio tap", st) }

        let aggUID = UUID().uuidString
        let dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Chitter Aggregate",
            kAudioAggregateDeviceUIDKey: aggUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: Self.tapList(uuid: desc.uuid.uuidString),
        ]
        st = AudioHardwareCreateAggregateDevice(dict as CFDictionary, &aggID)
        guard st == noErr else { cleanup(); throw AudioTapError.osStatus("Creating the aggregate device", st) }

        var fmtAddr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        st = AudioObjectGetPropertyData(tapID, &fmtAddr, 0, nil, &size, &asbd)
        guard st == noErr, let format = AVAudioFormat(streamDescription: &asbd) else { cleanup(); throw AudioTapError.noFormat }

        let resampler = self.resampler
        st = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, queue) { _, inData, _, _, _ in
            guard let buf = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inData, deallocator: nil) else { return }
            let out = resampler.convert(buf)
            if !out.isEmpty { onSamples(out) }
        }
        guard st == noErr, let procID else { cleanup(); throw AudioTapError.osStatus("Creating the IO proc", st) }
        st = AudioDeviceStart(aggID, procID)
        guard st == noErr else { cleanup(); throw AudioTapError.osStatus("Starting capture", st) }
        isRunning = true
    }

    public func stop() {
        guard isRunning else { return }
        cleanup()
        isRunning = false
    }

    private func cleanup() {
        if let procID, aggID != kAudioObjectUnknown {
            AudioDeviceStop(aggID, procID)
            AudioDeviceDestroyIOProcID(aggID, procID)
        }
        procID = nil
        if aggID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggID); aggID = kAudioObjectUnknown }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID); tapID = kAudioObjectUnknown }
    }
    deinit { cleanup() }
}
