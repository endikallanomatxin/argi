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
    node :: Node = (.value = 0, .pointer = $&fallback)
    destination : $&Node = $&node
    destination& = make_node(.value = 41)
    node.pointer& = 42
    status_code = node.value - 42
}
