main(.system: System = System()) -> (.status_code: Int32) := {
    argc ::= system.args | length(&_) | _.count

    if argc < 1 {
        status_code = 1
        return
    }

    status_code = 0
}
