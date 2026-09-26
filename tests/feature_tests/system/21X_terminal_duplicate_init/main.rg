main(.system: System) -> (.status_code: Int32) := {
    allocator ::= system.allocator
    assume allocator
    second := Terminal()
    status_code = 0
}
