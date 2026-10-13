FirstWriter: Type = ()

implement Init#(FirstWriter, ()) (
    .Result: Type = FirstWriter
    .init = (.args: ()) -> (.result: Result) {
        result = ()
    }
)

SecondWriter: Type = ()

implement Init#(SecondWriter, ()) (
    .Result: Type = SecondWriter
    .init = (.args: ()) -> (.result: Result) {
        result = ()
    }
)

Holder: Type = (
    .writer : $&Writer
)

set_first(
        .p      : $&Holder,
        .writer : $&FirstWriter,
    ) -> () := {
    p&.writer = writer
}

set_second(
        .p      : $&Holder,
        .writer : $&SecondWriter,
    ) -> () := {
    p&.writer = writer
}

main() -> (.status_code: Int32) := {
    first :: FirstWriter = FirstWriter()
    second :: SecondWriter = SecondWriter()
    holder :: Holder

    set_first(.p = $&holder, .writer = $&first)
    set_second(.p = $&holder, .writer = $&second)

    status_code = 0
}

implement Writer#(FirstWriter)(
    .write_byte = (
            .self : $&FirstWriter,
            .byte : UInt8
        ) -> (
            .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
        ) {
        _ ::= byte
        result = ..ok(.value = Void())
    }

    .flush = (
            .self : $&FirstWriter
        ) -> (
            .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
        ) {
        result = ..ok(.value = Void())
    }
)

implement Writer#(SecondWriter)(
    .write_byte = (
            .self : $&SecondWriter,
            .byte : UInt8
        ) -> (
            .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
        ) {
        _ ::= byte
        result = ..ok(.value = Void())
    }

    .flush = (
            .self : $&SecondWriter
        ) -> (
            .result : Errable#(.t: Void, .reasons: (..stream_write_failed, ..stream_flush_failed))
        ) {
        result = ..ok(.value = Void())
    }
)
