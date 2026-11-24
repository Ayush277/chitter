import Carbon.HIToolbox
import AppKit

/// Global hotkeys via Carbon RegisterEventHotKey: needs no Input Monitoring permission.
final class Hotkeys {
    private var refs: [EventHotKeyRef?] = []
    private var handlers: [UInt32: () -> Void] = [:]
    private var installed = false
    static let shared = Hotkeys()

    func register(keyCode: Int, modifiers: Int = controlKey | optionKey, id: UInt32, action: @escaping () -> Void) {
        if !installed {
            installed = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &hk)
                DispatchQueue.main.async { Hotkeys.shared.handlers[hk.id]?() }
                return noErr
            }, 1, &spec, nil, nil)
        }
        handlers[id] = action
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: OSType(0x43485452), id: id),
                            GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
    }
}
