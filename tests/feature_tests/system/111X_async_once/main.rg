work := once (.value: Int32) -> (.result: Int32) { result = value }
main := (.system: System) -> () {
    executor ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= to_virtual#(Executor)($&executor)
    first ::= unwrap_or_abort(.value = async#(work)(.args = (.value = 1)))
    second ::= unwrap_or_abort(.value = async#(work)(.args = (.value = 2)))
    _ = first
    _ = second
}
