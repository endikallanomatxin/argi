..missing
drops :: Int32 = 0

Owner := (.value: Int32)

implement Deinit<Owner> (
    .deinit = (.self: $&Owner) -> () {
        drops = drops + 1
    }
)

attempt := (.fail: Bool) -> (.result: Errable<Int32, (..missing)>) {
    if fail { result = ..error(.reason = ..missing) } else { result = ..ok 7 }
}

run := <.WriterType: Type: Writer<WriterType>> (
    .fail: Bool, .writer: $&WriterType = reach writer
) -> (.result: Int32 = 9) {
    local ::= Owner(1)
    value ::= attempt(fail)!!!
    result = value
}

unwrap := <.t: Type, .WriterType: Type: Writer<WriterType>> (
    .input: Errable<t, (..missing)>, .writer: $&WriterType = reach writer
) -> (.result: Int32 = 9) {
    result = ~input!!!
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume writer ::= $&system.terminal&.stderr
    if unwrap<.t: Int32>(attempt(false)) != 7 { abort }
    if unwrap<.t: Int32>(attempt(true)) != 9 { abort }
    if run(false) != 7 or drops != 1 { abort }
    if run(true) != 9 or drops != 2 { abort }
}
