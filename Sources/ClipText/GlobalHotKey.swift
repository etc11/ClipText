import Carbon

final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onPressed: () -> Void
    private static let signature: OSType = 0x534E4150 // SNAP

    init(onPressed: @escaping () -> Void) throws {
        self.onPressed = onPressed
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == GlobalHotKey.signature, identifier.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue().onPressed()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { throw HotKeyError.unavailable }
        let registered = RegisterEventHotKey(UInt32(kVK_ANSI_2), UInt32(cmdKey | shiftKey),
            EventHotKeyID(signature: Self.signature, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        guard registered == noErr else {
            if let handler { RemoveEventHandler(handler) }
            handler = nil
            throw HotKeyError.unavailable
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }

    enum HotKeyError: Error { case unavailable }
}
