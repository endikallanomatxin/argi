Buffer := #(.Item: Type, .count: UIntNative = 3) (.values: Array#(.n = count, .t: Item))

default_value := #(.Item: Type = Int32) (.value: Item = 7) -> (.result: Item) {
    result = value
}

Pair := #(.Left: Type, .Right: Type = Left) (.left: Left, .right: Right)

PairInitArgs: Type = #(.Left: Type, .Right: Type) (.left: Left, .right: Right)

implement#(.Left: Type, .Right: Type) Init#(Pair#(Left, Right), PairInitArgs#(Left, Right)) (
    .Result : Type = Pair#(Left, Right)

    .init = PairInitArgs#(Left, Right) -> (.result: Result) {
        result = (.left = left, .right = right)
    }
)

main := () -> () {
    pair: Pair#(Int32) = Pair#(Int32)(.left = 1, .right = 2)
    mixed ::= Pair#(.Left: Int32)(.left = 1, .right = true)
    if pair.right != 2 or mixed.right == false { abort }
    buffer: Buffer#(UInt8) = (.values = (1, 2, 3))
    if buffer.values[2] != 3 { abort }
    if default_value#()() != 7 { abort }
    if default_value#()(.value = true) == false { abort }
}
