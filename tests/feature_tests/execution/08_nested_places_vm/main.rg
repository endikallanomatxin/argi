Pair: Type = (.left: Int32, .right: Int32)

Box: Type = (.pairs: [2]Pair)

main() -> (.status_code: Int32 = 0) := {
    box :: Box = (.pairs = ((.left = 1, .right = 2), (.left = 3, .right = 4)))
    saved ::= box
    box.pairs[1].left = 40
    box.pairs[0].right = 2
    if saved.pairs[1].left != 3 { abort }
    status_code = box.pairs[1].left + box.pairs[0].right
}
