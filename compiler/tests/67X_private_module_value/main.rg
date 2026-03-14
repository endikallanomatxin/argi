main () -> (.status_code: Int32) := {
    dep := #import("./dep")
    status_code = dep._hidden_value
}
