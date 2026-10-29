Buffer := (.bytes: [4]UInt8)

implement Deinit#(Buffer) (
    .deinit = (.self: $&Buffer) -> () {

    }
)

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    buffer ::= Buffer(.bytes = zeroed#(.t: [4]UInt8)())
    writer ::= BufferedWriter#(.base_type: File)(
        .base = $&system.terminal&.stdout, .buffer = view(.self = $&buffer.bytes)
    )
    deinit(.self = $&buffer)
    Writer#().write_byte(.self = $&writer, .byte = 65)
}
