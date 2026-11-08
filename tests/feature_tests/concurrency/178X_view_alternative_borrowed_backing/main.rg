write := (.value: $&Int32) -> () { value& = 42 }
choose := (
    .old: ArrayView#(.t: Int32), .new: ArrayView#(.t: Int32), .pick_old: Bool
) -> (.result: ArrayView#(.t: Int32)) {
    if pick_old { result = old } else { result = new }
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    original: [1]Int32 = (7)
    old ::= view(&original)
    borrowed :: [1]Int32 = (0)
    new ::= view(&borrowed)
    future ::= unwrap_or_abort(.value = async#(write)(.args = (.value = $&borrowed[0])))
    selected ::= choose(.old = old, .new = new, .pick_old = false)
    pointer ::= unwrap_or_abort(.value = get_reference(.self = &selected, .index = 0))
    _ = pointer&
    _ = unwrap_or_abort(.value = await($&future))
}
