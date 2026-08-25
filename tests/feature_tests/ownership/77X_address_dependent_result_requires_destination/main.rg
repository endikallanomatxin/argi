Node : Type = (
    .value: Int32
    .pointer: $&Int32
)

Wrapper : Type = (
    .node: Node
)

make_node() -> (.node: Node) := {
    fallback :: Int32 = 0
    node = (
        .value = 1,
        .pointer = $&fallback,
    )
    node.pointer = $&node.value
}

main() -> (.status_code: Int32) := {
    wrapper ::= (
        .node = make_node(),
    )
    wrapper.node.pointer& = 9
    status_code = 0
}
