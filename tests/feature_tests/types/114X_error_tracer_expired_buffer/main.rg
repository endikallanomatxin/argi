Buffer : Type = (.bytes: [288]UInt8)
deinit(.self: $&Buffer) -> () := {}
main() -> (.status_code: Int32 = 0) := {
    buffer ::= Buffer(.bytes = zeroed#(.t: [288]UInt8)())
    tracer ::= FixedSizeErrorTracer(.buffer = view($&buffer.bytes))
    deinit(.self = $&buffer)
    add_context(.self = $&tracer, .location = error_location_id(), .context = "expired")
}
