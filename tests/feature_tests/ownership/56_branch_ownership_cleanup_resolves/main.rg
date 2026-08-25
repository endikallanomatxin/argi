main(.system: System, .condition: Bool = false) -> (.status_code: Int32) := {
    owner ::= allocate_owned(.self = system.allocator, .size = 1)

    if condition {
        moved ::= ~owner
        if moved.size == 1 {
            status_code = 0
        }
    }

    status_code = 0
}
