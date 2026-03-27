main(.system: System = System()) -> (.status_code: Int32) := {
    argc ::= length(.self = system.args).count
    if argc < 1 {
        status_code = 1
        return
    }

    arg0 ::= system.args[0]
    arg0_explicit ::= argument_view_at(.self = system.args, .index = 0)

    if arg0.length != arg0_explicit.length {
        status_code = 2
        return
    }

    if arg0.length < 1 {
        status_code = 3
        return
    }

    if bytes_get(.view = &arg0, .index = 0).byte != bytes_get(.view = &arg0_explicit, .index = 0).byte {
        status_code = 4
        return
    }

    status_code = 0
}
