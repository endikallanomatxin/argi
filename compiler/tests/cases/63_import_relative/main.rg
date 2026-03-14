main () -> (.status_code: Int32) := {
    dep := #import("./dep")
    status_code = dep.read_status()
}
