dep := import("./dep")
Product#(.Left: Type, .Right: Type): Contract = (
    .Result: Type

    multiply(.left: Left, .right: Right) -> (.value: Result) where {}
)
satisfies Product#(dep.Row, dep.Column) = (.Result: Int32)
main() -> () := {}
