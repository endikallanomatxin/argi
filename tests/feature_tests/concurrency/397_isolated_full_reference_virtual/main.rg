Read#(.R: Type): Contract = (
    .read: (.receiver: R) -> (.value: Int32) where reads(receiver)
)
Cell := (.value: Int32)
implement ConcurrentAlias#(Cell) ()
implement Read#($$&Cell) (
    .read = (.receiver: $$&Cell) -> (.value: Int32) {
        view ::= trusted_concurrent_view(.shared = receiver)
        value = view&.value
    }
)
read := (.cell: $$&Cell) -> (.value: Int32) {
    reader: Virtual#(Read) = Virtual#(Read)(cell)
    value = reader.read().value
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    cell ::= Cell(42)
    shared ::= $$&cell
    future ::= unwrap_or_abort(async#(read)(.args = (.cell = shared)))
    if unwrap_or_abort(await($&future)) != 42 { abort }
    recover_ordinary(.owner = $&cell)
}
