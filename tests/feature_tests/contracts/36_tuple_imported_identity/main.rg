dep := import("./dep")
Product#(.Left: Type, .Right: Type): Contract = (
    .Result: Type

    .local_product: (.left: Left, .right: Right) -> (.value: Result) where {}
)
implement Product#(dep.Row, dep.Column) (.Result: Type = Int64, .local_product = _impl_local_product_373)
_impl_local_product_373 := (.left: dep.Row, .right: dep.Column) -> (.value: Int64)  { value = 7 }
main() -> () := {
    if dep.multiply(dep.Row(), dep.Column()).value != 42 { abort }
    if local_product(dep.Row(), dep.Column()).value != 7 { abort }
}
