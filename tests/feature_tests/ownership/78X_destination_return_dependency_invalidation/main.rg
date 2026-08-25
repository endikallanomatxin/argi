Node : Type = (
    .value: Int32
    .pointer: &Int32
)

make_node() -> (.node: Node) := {
    fallback :: Int32 = 0
    node = (
        .value = 1,
        .pointer = &fallback,
    )
    node.pointer = &node.value
}

read(.value: &Int32) -> () := {}

main() -> (.status_code: Int32) := {
    node ::= make_node()
    pointer ::= node.pointer
    node.value = 2
    read(.value = pointer)
    status_code = 0
}
