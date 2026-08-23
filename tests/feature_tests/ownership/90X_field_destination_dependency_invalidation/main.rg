Node : Type = (.value: Int32, .pointer: &Int32)
Wrapper : Type = (.node: Node)

make_node() -> (.node: Node) := {
    fallback :: Int32 = 0
    node = (.value = 1, .pointer = &fallback)
    node.pointer = &node.value
}

read(.value: &Int32) -> () := {}

main() -> (.status_code: Int32) := {
    fallback :: Int32 = 0
    wrapper :: Wrapper = (.node = (.value = 0, .pointer = &fallback))
    wrapper.node = make_node()
    pointer ::= wrapper.node.pointer
    wrapper.node.value = 2
    read(.value = pointer)
    status_code = 0
}
