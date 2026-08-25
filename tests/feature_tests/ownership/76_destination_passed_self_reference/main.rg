Node : Type = (
    .value: Int32
    .pointer: $&Int32
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
    node ::= make_node()
    node.pointer& = 9
    if node.value == 9 {
        status_code = 0
    } else {
        status_code = 1
    }
}
