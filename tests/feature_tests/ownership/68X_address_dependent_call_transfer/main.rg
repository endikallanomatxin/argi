Node : Type = (
    .value: Int32
    .pointer: $&Int32
)

deinit(.self: $$&Node) -> () := {}
consume(.node: Node) -> () := {}

main() -> (.status_code: Int32) := {
    fallback :: Int32 = 0
    node :: Node = (
        .value = 1,
        .pointer = $&fallback,
    )
    node.pointer = $&node.value
    consume(.node = ~node)
    status_code = 0
}
