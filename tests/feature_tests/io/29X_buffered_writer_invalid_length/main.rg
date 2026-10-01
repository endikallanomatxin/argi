main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= $&GeneralPurposeAllocator(.allocator = system.page_allocator)
    buffered ::= unwrap_or_abort(.value = BufferedWriter#(.base_type: File)(.base = $&system.terminal&.stdout, .capacity = 4))
    -- A caller-corrupted length must not become an unchecked bulk-read range.
    buffered.length = 5
    flush(.self = $&buffered)
}
