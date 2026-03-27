main () -> (.status_code: Int32) := {
    dep := #import("./dep")
    hidden : dep._HiddenStatus = (.code = 0)
    status_code = hidden.code
}
