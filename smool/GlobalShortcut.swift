import Carbon

@MainActor
final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) throws {
        self.action = action

        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }

                var identifier = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard status == noErr, identifier.signature == 0x534D4F4C, identifier.id == 1 else {
                    return OSStatus(eventNotHandledErr)
                }

                MainActor.assumeIsolated {
                    Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue().action()
                }
                return noErr
            },
            1,
            &event,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )

        guard handlerStatus == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(handlerStatus))
        }

        let identifier = EventHotKeyID(signature: 0x534D4F4C, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), identifier, GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotKey)

        guard status == noErr else {
            stop()
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }
}
