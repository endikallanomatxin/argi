Buffer#(.Item: Type, .count: UIntNative = 3): Type = (.values: Array#(.n = count, .t: Item))

default_value#(.Item: Type = Int32)(.value: Item = 7) -> (.result: Item) := {
    result = value
}

Pair#(.Left: Type, .Right: Type = Left): Type = (.left: Left, .right: Right)

implement#(.Left: Type, .Right: Type) Init#(Pair#(Left, Right), (.left: Left, .right: Right)) (
    .Result : Type = Pair#(Left, Right)
    .init   = (.args: (.left: Left, .right: Right)) -> (.result: Result) {
        result = (.left = args.left, .right = args.right)
    }
)

main() -> () := {
    pair: Pair#(Int32) = Pair#(Int32)(.left = 1, .right = 2)
    mixed ::= Pair#(.Left: Int32)(.left = 1, .right = true)
    if pair.right != 2 or mixed.right == false { abort }
    buffer: Buffer#(UInt8) = (.values = (1, 2, 3))
    if buffer.values[2] != 3 { abort }
    if default_value#()() != 7 { abort }
    if default_value#()(.value = true) == false { abort }
}
