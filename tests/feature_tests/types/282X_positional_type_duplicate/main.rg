Pair#(.left: Type, .right: Type): Type = (.left: left, .right: right)

main() -> () := { value: Pair#(Int32, .left: Bool) = (.left = 1, .right = true) }
