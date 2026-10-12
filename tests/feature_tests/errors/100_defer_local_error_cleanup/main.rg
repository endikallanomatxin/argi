..failure
order :: Int32 = 0
drops :: Int32 = 0

Owner: Type = (.value: Int32)

Owner deinit(.self: $&Owner) -> () := { drops = drops + 1 }

fail() -> (.result: Errable#(Void, (..failure))) := {
    result = ..error(.reason = ..failure)
}

finish(
        .body_fails : Bool,
        .state      : $&Int32,
        .writer     : $&Writer = reach writer
    ) -> (
        .result : Int32 = 1
    ) := {
    owner ::= Owner(1)
    #defer { state&= state&* 10 + 3 }
    #defer {
        deferred_owner ::= Owner(3)
        fail() handle error {
            state&= state&* 10 + 2
            result = 1
            report_trace(.tracer = error.tracer, .writer = writer) handle ignored {}
        }
    }
    #defer {
        while true {
            state&= state&* 10 + 1
            break
        }
    }
    if body_fails { fail()!!! }
    result = 0
}

finish_generic#(.t: Type)(.value: t, .state: $&Int32) -> (.result: Int32 = 0) := {
    owner ::= Owner(2)
    #defer { state&= state&* 10 + 3 }
    #defer {
        deferred_owner ::= Owner(3)
        fail() handle error {
            state&= state&* 10 + 2
            result = 1
        }
    }
    #defer {
        while true {
            state&= state&* 10 + 1
            break
        }
    }
}

BrokenWriter: Type = ()

main(.system: System) -> () := {
    assume writer ::= $&system.terminal&.stderr
    if finish(false, $&order, .writer = writer) != 1 or order != 123 or drops != 2 { abort }
    order = 0
    if finish(true, $&order, .writer = writer) != 1 or order != 123 or drops != 4 { abort }
    order = 0
    if finish_generic#(.t: Int32)(7, $&order) != 1 or order != 123 or drops != 6 { abort }
    order = 0
    broken ::= BrokenWriter()
    if finish(false, $&order, .writer = $&broken) != 1 or order != 123 or drops != 8 { abort }
}

implement Writer#(BrokenWriter)(
    .write_byte = (
            .self : $&BrokenWriter,
            .byte : UInt8
        ) -> (
            .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
        ) {
        result = ..error(.reason = ..stream_write_failed)
    }

    .flush = (
            .self : $&BrokenWriter
        ) -> (
            .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
        ) {
        result = ..error(.reason = ..stream_flush_failed)
    }
)
