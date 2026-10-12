Product#(.Result: Type): contract#(.Left: Type, .Right: Type) = (
    multiply(.left: Left, .right: Right) -> (.value: Result) where {}
)
satisfies Product#(Int32, Int32) = (.Result: Int64)
multiply(.left: Int32, .right: Int32) -> (.value: Int64) := { value = 0 }
Box#(.T: Type): Type = (.value: Product#(T, T).Result)
read_box(.box: &Box#(Int32)) -> (.value: Int64) := { value = box&.value }
main() -> () := {
    box ::= Box#(Int32)(42)
    if read_box(&box).value != 42 { abort }
}
