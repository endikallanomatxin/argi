FirstWriter: Type = ()

implement Init<FirstWriter, ()> (
    .Result : Type = FirstWriter
    .init   = (.args: ()) -> (.result: Result) {
        result = ()
    }
)

SecondWriter := (.marker: Int32 = 0)

implement Init<SecondWriter, ()> (
    .Result : Type = SecondWriter
    .init   = (.args: ()) -> (.result: Result) {
        result = ()
    }
)

Holder := <.WriterType: Type: Writer<WriterType>> (
    .writer : $&WriterType
)

set_first := (.p: $&Holder<FirstWriter>, .writer: $&FirstWriter) -> () {
    p&.writer = writer
}

set_second := (.p: $&Holder<FirstWriter>, .writer: $&SecondWriter) -> () {
    p&.writer = writer
}

main := () -> (.status_code: Int32) {
    first :: FirstWriter = FirstWriter()
    second :: SecondWriter = SecondWriter()
    holder :: Holder<FirstWriter>

    set_first(.p = $&holder, .writer = $&first)
    set_second(.p = $&holder, .writer = $&second)

    status_code = 0
}

implement Writer<FirstWriter> (
    .write_byte = (.self: $&FirstWriter, .byte: UInt8) -> (
        .result: Errable<.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed)>
    ) {
        _ ::= byte
        result = ..ok(.value = Void())
    }

    .flush = (.self: $&FirstWriter) -> (
        .result: Errable<.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed)>
    ) {
        result = ..ok(.value = Void())
    }
)

implement Writer<SecondWriter> (
    .write_byte = (.self: $&SecondWriter, .byte: UInt8) -> (
        .result: Errable<.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed)>
    ) {
        _ ::= byte
        result = ..ok(.value = Void())
    }

    .flush = (.self: $&SecondWriter) -> (
        .result: Errable<.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed)>
    ) {
        result = ..ok(.value = Void())
    }
)
