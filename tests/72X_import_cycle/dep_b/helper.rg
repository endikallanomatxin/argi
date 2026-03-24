dep_a := #import("../dep_a")

read_b () -> (.status_code: Int32) := {
    status_code = dep_a.read_a()
}
