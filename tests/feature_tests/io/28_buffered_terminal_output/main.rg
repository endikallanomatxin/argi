main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= $&GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume writer ::= $&unwrap_or_abort(
        .value = BufferedWriter#(.base_type: File)(.base = $&system.terminal&.stdout, .capacity = 4),
    )
    unwrap_or_abort(.value = print("Buffered output\n"))
    -- The pending tail is written by scope cleanup.
    unwrap_or_abort(.value = write_byte(.self = writer, .byte = 79))
    unwrap_or_abort(.value = write_byte(.self = writer, .byte = 75))
}
