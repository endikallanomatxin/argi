Node : Type = (
    .value: Int32
    .pointer: $&Int32
)

make_node(.value: Int32) -> (.node: Node) := {
    fallback :: Int32 = 0
    node = (.value = value, .pointer = $&fallback)
    node.pointer = $&node.value
}

main() -> (.status_code: Int32) := {
    fallback :: Int32 = 0
    nodes :: Array#(.n = 1, .t: Node) = ((.value = 0, .pointer = $&fallback),)
    nodes[0] = make_node(.value = 41)
    nodes[0].pointer& = 42
    status_code = nodes[0].value - 42
}
