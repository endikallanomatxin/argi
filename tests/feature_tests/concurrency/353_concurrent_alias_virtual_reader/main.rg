Reader#(.T: Type): Contract = (
    .read: (.receiver: $$&T) -> (.value: Int32) where { no_access() }
)
Cell := (.value: Int32)
implement ConcurrentAlias#(Cell) ()
implement Reader#(Cell) (
    .read = (.receiver: $$&Cell) -> (.value: Int32) {
        view ::= trusted_concurrent_view(.shared = receiver)
        value = view&.value
    }
)

main := () -> () {
    cell ::= Cell(1)
    shared ::= $$&cell
    reader ::= Virtual#(Reader)(shared)
    if Reader#().read(&reader).value != 1 { abort }
}
