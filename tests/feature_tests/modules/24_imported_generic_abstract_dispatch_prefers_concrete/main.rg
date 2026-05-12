main(.system: System = System()) -> (.status_code: Int32) := {
    dep := #import("./dep")

    status_code = dep.pick(.value = 123).status_code
}
