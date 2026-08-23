Node : Type = (.value: Int32, .pointer: &Int32)

make_node() -> (.node: Node) := {
    fallback :: Int32 = 0
    node = (.value = 1, .pointer = &fallback)
    node.pointer = &node.value
}

read(.value: &Int32) -> () := {}

main() -> (.status_code: Int32) := {
    fallback :: Int32 = 0
    nodes :: Array#(.n = 1, .t: Node) = ((.value = 0, .pointer = &fallback),)
    nodes[0] = make_node()
    pointer ::= nodes[0].pointer
    nodes[0].value = 2
    read(.value = pointer)
    status_code = 0
}
