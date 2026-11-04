read := (.items: &[2]Int32) -> (.result: Int32) { result = items&[0] + items&[1] }
write := (.items: $&[2]Int32) -> () {
    items&[0] = 20
    items&[1] = 22
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&provider)
    items :: [2]Int32 = (1, 2)
    first ::= unwrap_or_abort(.value = async#(read)(.args = (.items = &items)))
    if unwrap_or_abort(.value = await($&first)) != 3 { abort }
    second ::= unwrap_or_abort(.value = async#(write)(.args = (.items = $&items)))
    _ = unwrap_or_abort(.value = await($&second))
    if items[0] != 20 or items[1] != 22 { abort }
}
