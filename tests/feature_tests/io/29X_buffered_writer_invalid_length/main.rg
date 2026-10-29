main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    buffered ::= BufferedWriter#(.base_type: File)(
        .base = $&system.terminal&.stdout, .buffer = view(.self = $&zeroed#(.t: [4]UInt8)())
    )
    -- A caller-corrupted length must not become an unchecked bulk-read range.
    buffered.length = 5
    Writer#().flush(.self = $&buffered)
}
