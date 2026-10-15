Pair#(.left: Type, .right: Type): Type = (.left: left, .right: right)

main() -> () := { value: Pair#(Int32, Bool, UInt8) = (.left = 1, .right = true) }
