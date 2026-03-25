main(.system: System = System()) -> (.status_code: Int32) := {
    argc ::= argument_count(.self = system.args).count
    if argc < 1 {
        status_code = 1
        return
    }

    arg0_text ::= argument_at(.self = system.args, .index = 0)
    arg0_ptr ::= pointer(.self = &arg0_text)
    arg0_len ::= strlen(.string = arg0_ptr).length

    arg0_view ::= argument_view_at(.self = system.args, .index = 0)
    if arg0_view.length != arg0_len {
        status_code = 2
        return
    }

    if arg0_view.length < 1 {
        status_code = 3
        return
    }

    first_ptr : &UInt8 = cast#(.to: &UInt8)(.value = cast#(.to: UIntNative)(.value = arg0_ptr))
    if bytes_get(.view = &arg0_view, .index = 0).byte != first_ptr& {
        status_code = 4
        return
    }

    status_code = 0
}
