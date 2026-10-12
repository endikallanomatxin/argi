dep := import("./dep")
Product#(.Result: Type): Contract#(.Left: Type, .Right: Type) = (
    multiply(.left: Left, .right: Right) -> (.value: Result) where {}
)
satisfies Product#(dep.Row, dep.Column) = (.Result: Int32)
main() -> () := {}
