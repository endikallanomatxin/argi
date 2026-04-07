main(.system: System = System()) -> (.status_code: Int32) := {
    dep := #import("./dep")

    status_code = dep.load(.allocator = system.allocator).status_code
}
