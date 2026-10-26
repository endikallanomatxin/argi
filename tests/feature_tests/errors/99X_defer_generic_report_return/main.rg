fail := () -> !Void = ..ok Void() {}

finish := <.t: Type, .WriterType: Type: Writer<WriterType>> (
    .value: t, .writer: $&WriterType = reach writer
) -> () { defer { fail()!!! } }

main := (.system: System) -> () {
    assume writer ::= $&system.terminal&.stderr
    finish<.t: Int32> (1)
}
