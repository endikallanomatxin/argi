main () -> (.status_code: Int32) := {
    dep_a := #import("./dep_a")
    status_code = dep_a.read_a()
}
