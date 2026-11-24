import Foundation
import CoreAudio

public struct AudioProcess: Equatable, Sendable {
    public var pid: pid_t
    public var bundleID: String
    public var isRunningInput: Bool
    public var isRunningOutput: Bool
    public init(pid: pid_t, bundleID: String, isRunningInput: Bool, isRunningOutput: Bool) {
        self.pid = pid; self.bundleID = bundleID; self.isRunningInput = isRunningInput; self.isRunningOutput = isRunningOutput
    }
}

public struct CallInfo: Equatable, Sendable {
    public var app: String          // human label, e.g. "Zoom", "Google Chrome (browser call)"
    public var bundleID: String
}

/// Detects an active call by asking Core Audio which processes currently have the microphone open (macOS 14.4+).
/// Works for native apps and for browser tabs (Meet, Teams web, …) without an extension or any extra permission.
public enum CallDetector {
    /// bundle-ID prefix → label. Browsers count because a browser with the mic open is almost always a call.
    public static let known: [(prefix: String, label: String)] = [
        ("us.zoom", "Zoom"), ("com.microsoft.teams", "Microsoft Teams"), ("com.apple.FaceTime", "FaceTime"),
        ("com.cisco.webex", "Webex"), ("Cisco-Systems.Spark", "Webex"), ("com.tinyspeck.slackmacgap", "Slack huddle"),
        ("com.hnc.Discord", "Discord"), ("com.skype", "Skype"), ("net.whatsapp", "WhatsApp"), ("ru.keepcoder.Telegram", "Telegram"),
        ("com.google.Chrome", "Chrome (browser call)"), ("com.apple.Safari", "Safari (browser call)"), ("com.apple.WebKit", "Safari (browser call)"),
        ("org.mozilla.firefox", "Firefox (browser call)"), ("com.microsoft.edgemac", "Edge (browser call)"),
        ("com.brave.Browser", "Brave (browser call)"), ("company.thebrowser.Browser", "Arc (browser call)"),
        ("ai.perplexity.comet", "Comet (browser call)"), ("com.operasoftware", "Opera (browser call)"), ("com.vivaldi", "Vivaldi (browser call)"),
    ]

    /// Pure classification, unit-testable. Ignores Chitter itself.
    public static func classify(_ procs: [AudioProcess], ownPID: pid_t = getpid()) -> CallInfo? {
        for p in procs where p.isRunningInput && p.pid != ownPID {
            if let k = known.first(where: { p.bundleID.hasPrefix($0.prefix) }) { return CallInfo(app: k.label, bundleID: p.bundleID) }
        }
        return nil
    }

    public static func audioProcesses() -> [AudioProcess] {
        func addr(_ s: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(mSelector: s, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        }
        var a = addr(kAudioHardwarePropertyProcessObjectList); var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids) == noErr else { return [] }
        func u32(_ id: AudioObjectID, _ s: AudioObjectPropertySelector) -> UInt32 {
            var v: UInt32 = 0; var sz = UInt32(MemoryLayout<UInt32>.size); var ad = addr(s)
            AudioObjectGetPropertyData(id, &ad, 0, nil, &sz, &v); return v
        }
        return ids.map { id in
            var bid: CFString = "" as CFString; var sz = UInt32(MemoryLayout<CFString>.size); var ad = addr(kAudioProcessPropertyBundleID)
            let ok = withUnsafeMutablePointer(to: &bid) { AudioObjectGetPropertyData(id, &ad, 0, nil, &sz, $0) } == noErr
            return AudioProcess(pid: pid_t(u32(id, kAudioProcessPropertyPID)), bundleID: ok ? bid as String : "",
                                isRunningInput: u32(id, kAudioProcessPropertyIsRunningInput) != 0,
                                isRunningOutput: u32(id, kAudioProcessPropertyIsRunningOutput) != 0)
        }
    }

    public static func current() -> CallInfo? { classify(audioProcesses()) }
}

/// Polls for calls, with hysteresis so a brief mute (mic released for a few seconds) doesn't end the meeting.
public final class CallWatcher: @unchecked Sendable {
    public var onStart: (@Sendable (CallInfo) -> Void)?
    public var onEnd: (@Sendable () -> Void)?
    private var timer: DispatchSourceTimer?
    private var active = false
    private var missing = 0
    private let graceTicks: Int
    private let interval: Double
    private let probe: @Sendable () -> CallInfo?

    public init(interval: Double = 2, graceSeconds: Double = 12, probe: @escaping @Sendable () -> CallInfo? = { CallDetector.current() }) {
        self.interval = interval; graceTicks = max(1, Int(graceSeconds / interval)); self.probe = probe
    }

    /// One poll step; exposed so tests can drive it without timers.
    public func tick() {
        if let info = probe() {
            missing = 0
            if !active { active = true; onStart?(info) }
        } else if active {
            missing += 1
            if missing >= graceTicks { active = false; missing = 0; onEnd?() }
        }
    }
    public func start() {
        stop()
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        t.schedule(deadline: .now(), repeating: interval); t.setEventHandler { [weak self] in self?.tick() }
        t.resume(); timer = t
    }
    public func stop() { timer?.cancel(); timer = nil; active = false; missing = 0 }
    public var isCallActive: Bool { active }
}
