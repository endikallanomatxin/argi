DummyWriter : Type = (
    .flush_count: Int32 = 0
)

write_byte(.self: $&DummyWriter, .byte: UInt8) -> () := {
    _ ::= self
}

flush(.self: $&DummyWriter) -> () := {
    self& = (
        .flush_count = self&.flush_count + 1
    )
}

DummyWriter implements Writer

Wrapper#(.base_type: Type: Writer) : Type = (
    .base: $&base_type
)

write_byte#(.base_type: Type: Writer)(
    .self: $&Wrapper#(.base_type: base_type),
    .byte: UInt8,
) -> () := {
    write_byte(.self = self&.base, .byte = byte)
}

flush#(.base_type: Type: Writer)(
    .self: $&Wrapper#(.base_type: base_type),
) -> () := {
    flush(.self = self&.base)
}

Wrapper#(.base_type: Type: Writer) implements Writer

accept(
    .writer: $&Writer,
) -> (.status_code: Int32) := {
    flush(.self = writer)
    status_code = 0
}

main() -> (.status_code: Int32) := {
    base :: DummyWriter = (
        .flush_count = 0
    )
    wrapper :: Wrapper#(.base_type: DummyWriter) = (
        .base = $&base
    )

    _ ::= accept(.writer = $&wrapper)
    status_code = 0
}
