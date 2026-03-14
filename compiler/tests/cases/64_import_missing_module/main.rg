main () -> (.status_code: Int32) := {
    dep := #import("./missing_dep")
    status_code = dep.read_status()
}
