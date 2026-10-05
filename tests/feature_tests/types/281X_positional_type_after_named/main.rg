Pair#(.left: Type, .right: Type): Type = (.left: left, .right: right)
main() -> () := { value: Pair#(.left: Int32, Bool) = (.left = 1, .right = true) }
