Buffer := (.bytes: [288]UInt8)

implement Deinit<Buffer> (
    .deinit = (.self: $&Buffer) -> () {

    }
)

main := (.system: System) -> (.status_code: Int32 = 0)  {
    assume ffi := system.ffi
    buffer ::= Buffer(.bytes = zeroed<.t: [288]UInt8>())
    tracer ::= FixedSizeErrorTracer(.buffer = view($&buffer.bytes))
    deinit(.self = $&buffer)
    ErrorTracer<>.add_context(
        .self     = $&tracer
        .location = error_location_id()
        .context  = "expired"
    )
}
