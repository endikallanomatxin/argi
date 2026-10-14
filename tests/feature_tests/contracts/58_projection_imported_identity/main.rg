dep := import("./dep")
Product#(.Left: Type, .Right: Type): Contract = (
    .Result: Type

    .local_product: (.left: Left, .right: Right) -> (.value: Result) where {}
)
satisfies dep.Product#(dep.Row, dep.Column) = (.Result: Int32)
implement Product#(dep.Row, dep.Column) (.Result: Type = Int64, .local_product = _impl_local_product_408)
multiply(.left: dep.Row, .right: dep.Column) -> (.value: dep.Product#(dep.Row, dep.Column).Result) := { value = 42 }
_impl_local_product_408 := (.left: dep.Row, .right: dep.Column) -> (.value: Product#(dep.Row, dep.Column).Result)  { value = 7 }
main() -> () := {
    if multiply(dep.Row(), dep.Column()).value != 42 { abort }
    if local_product(dep.Row(), dep.Column()).value != 7 { abort }
}
