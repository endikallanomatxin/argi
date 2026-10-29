dep := import ("./dep")

Product#(.Left: Type, .Right: Type): Contract = (
    .Result : Type

    .local_product : (.left: Left, .right: Right) -> (.value: Result) where {}
)

implement Product#(dep.Row, dep.Column) (
    .Result        : Type = Int64,
    .local_product = _impl_local_product_408
)

_impl_local_product_408 := (.left: dep.Row, .right: dep.Column) -> (
    .value : Product#(dep.Row, dep.Column).Result
) { value = 7 }

main := () -> () {
    assume error_tracer ::= $&noop_error_tracer
    if dep.multiply(dep.Row(), dep.Column()).value != 42 { abort }
    if local_product(dep.Row(), dep.Column()).value != 7 { abort }
}
