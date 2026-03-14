dep_b := #import("../dep_b")

read_a () -> (.status_code: Int32) := {
    status_code = dep_b.read_b()
}
