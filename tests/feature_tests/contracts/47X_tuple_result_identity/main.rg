Reader: contract = ()
Cell: Type = ()
Cell satisfies Reader
Product#(.Result: Type): contract#(.Left: Type, .Right: Type) = (
    multiply(.left: Left, .right: Right) -> (.value: Result) where {}
)
satisfies Product#(Int32, Int64) = (.Result: Reader)
multiply(.left: Int32, .right: Int64) -> (.value: Cell) := { value = Cell() }
main() -> () := {}
