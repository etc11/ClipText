// Session state prevents repeated authorization dialogs when the system's
// preflight result has not caught up with a successful authorization request.
// This is not an OS permission grant: the capture backend still enforces TCC.
struct ScreenCapturePermission {
    private var grantedInSession = false
    private var requestedInSession = false

    mutating func authorize(preflight: () -> Bool, request: () -> Bool) -> Bool {
        if grantedInSession { return true }
        if preflight() {
            grantedInSession = true
            return true
        }
        guard !requestedInSession else { return false }
        requestedInSession = true
        grantedInSession = request()
        return grantedInSession
    }

    mutating func captureFailed() {
        // A revoked permission must not leave us indefinitely trusting the
        // session hint. Recheck on the next attempt without reprompting.
        grantedInSession = false
    }
}
