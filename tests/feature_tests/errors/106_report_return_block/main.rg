..missing
calls :: Int32 = 0
drops :: Int32 = 0

Owner := (.value: Int32)

implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () {
        drops = drops + 1
    }
)

attempt := (.fail: Bool) -> (.result: Errable#(Int32, (..missing))) {
    calls = calls + 1
    if fail { result = ..error(.reason = ..missing) } else { result = ..ok 7 }
}

finish := #(.WriterType: Type: Writer#(WriterType)) (
    .fail: Bool, .writer: $&WriterType = reach writer
) -> (.result: Int32 = 0) {
    owner ::= Owner(1)
    value ::= attempt(fail)!!! {
        action_owner ::= Owner(2)
        result = 9
    }
    result = value
}

unwrap := #(.t: Type, .WriterType: Type: Writer#(WriterType)) (
    .input: Errable#(t, (..missing)), .writer: $&WriterType = reach writer
) -> (.result: Int32 = 0) {
    owner ::= Owner(3)
    value ::= ~input!!! {
        action_owner ::= Owner(4)
        result = 11
    }
    result = 7
}

condition := (.fail: Bool) -> (.result: Errable#(Bool, (..missing))) {
    if fail { result = ..error(.reason = ..missing) } else { result = ..ok true }
}

check_conditions := #(.WriterType: Type: Writer#(WriterType)) (
    .fail: Bool, .writer: $&WriterType = reach writer
) -> (.result: Int32 = 0) {
    if condition(false)!!! { result = 1 }
    if [condition(fail)!!! { result = 13 }] { result = 2 }
}

identity := (.input: Int32) -> (.value: Int32) { value = input }

finish_argument := (.fail: Bool, .writer: $&File = reach writer) -> (.result: Int32 = 0) {
    if identity(attempt(fail)!!! { result = 17 }) == 7 { result = 7 }
}

BrokenWriter: Type = ()

main := (.system: System) -> () {
    assume writer ::= $&system.terminal&.stderr
    if finish(false) != 7 or calls != 1 or drops != 1 { abort }
    if finish(true) != 9 or calls != 2 or drops != 3 { abort }
    if unwrap#(.t: Int32)(attempt(false)) != 7 or drops != 4 { abort }
    if unwrap#(.t: Int32)(attempt(true)) != 11 or drops != 6 { abort }
    if check_conditions(false) != 2 or check_conditions(true) != 13 { abort }
    if finish_argument(false) != 7 or finish_argument(true) != 17 { abort }
    broken ::= BrokenWriter()
    if finish(true, .writer = $&broken) != 9 or drops != 8 { abort }
}

implement Writer#(BrokenWriter) (
    .write_byte = (.self: $&BrokenWriter, .byte: UInt8) -> (
        .result: Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) {
        result = ..error(.reason = ..stream_write_failed)
    }

    .flush = (.self: $&BrokenWriter) -> (
        .result: Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) {
        result = ..error(.reason = ..stream_flush_failed)
    }
)
