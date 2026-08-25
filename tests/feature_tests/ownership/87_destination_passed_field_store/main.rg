Node : Type = (
    .value: Int32
    .pointer: $&Int32
)

Wrapper : Type = (
    .node: Node
)

make_node(.value: Int32) -> (.node: Node) := {
    fallback :: Int32 = 0
    node = (.value = value, .pointer = $&fallback)
    node.pointer = $&node.value
}

main() -> (.status_code: Int32) := {
    fallback :: Int32 = 0
    wrapper :: Wrapper = (.node = (.value = 0, .pointer = $&fallback))
    wrapper.node = make_node(.value = 41)
    wrapper.node.pointer& = 42
    status_code = wrapper.node.value - 42
}
