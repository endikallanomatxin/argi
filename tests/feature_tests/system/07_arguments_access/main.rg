main := (.system: System) -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    assume ffi := system.ffi
    argc ::= length(.self = system.args).count
    if argc < 1 {
        status_code = 1
        return
    }

    arg0_text ::= argument_at(.self = system.args, .index = 0)
    arg0_ptr: &CChar = arg0_text
    arg0_len ::= strlen(.string = arg0_ptr).length

    arg0_view ::= unwrap_or_abort(.value = argument_view_at(.self = system.args, .index = 0))
    if byte_length(&arg0_view).count != arg0_len {
        status_code = 2
        return
    }

    if byte_length(&arg0_view).count < 1 {
        status_code = 3
        return
    }

    first_ptr ::= trusted_reinterpret_reference#(.from: CChar, .to: UInt8)(
        .base = arg0_ptr
    ).reference
    if unwrap_or_abort(.value = bytes_get(.view = &arg0_view, .index = 0)) != first_ptr&{
        status_code = 4
        return
    }

    status_code = 0
}
