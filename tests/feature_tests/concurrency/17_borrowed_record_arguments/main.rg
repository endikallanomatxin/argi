BorrowedBox := (.source: &Int32, .target: $&Int32)
copy := (.box: BorrowedBox) -> (.result: Int32) {
    box.target& = box.source&
    result = box.target&
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    source :: Int32 = 42
    target :: Int32 = 0
    box: BorrowedBox = (.source = &source, .target = $&target)
    future ::= unwrap_or_abort(.value = async#(copy)(.args = (.box = box)))
    if unwrap_or_abort(.value = await($&future)) != 42 { abort }
    if target != 42 { abort }
}
