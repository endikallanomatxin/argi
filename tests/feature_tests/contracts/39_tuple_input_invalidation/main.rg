Reset#(.Left: Type, .Right: Type): Contract = (
    reset(.left: $&Left, .right: &Right) -> () where invalidates(left)
)
satisfies Reset#(Int32, Int64)
reset(.left: $&Int32, .right: &Int64) -> () := { left&= 42 }
main() -> () := {
    left :: Int32 = 7
    right :: Int64 = 9
    reset($&left, &right)
    if left != 42 { abort }
}
