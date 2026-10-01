main(.system: System) -> (.status_code: Int32 = 0) := {
    buffered ::= BufferedWriter#(.base_type: File)(.base = $&system.terminal&.stdout, .buffer = array_view(.array = $&zeroed#(.t: [4]UInt8)()))
    -- A caller-corrupted length must not become an unchecked bulk-read range.
    buffered.length = 5
    flush(.self = $&buffered)
}
