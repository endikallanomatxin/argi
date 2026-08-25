Node : Type = (
    .value: Int32
    .pointer: $&Int32
)

deinit(.self: $&Node) -> () #invalidates(self) := {}

consume(.node: Node) -> (.ok: Bool) := {
    node.pointer& = 7
    ok = node.value == 7
}

main() -> (.status_code: Int32) := {
    fallback :: Int32 = 0
    node :: Node = (
        .value = 1,
        .pointer = $&fallback,
    )
    node.pointer = $&node.value
    result ::= consume(.node = ~node)
    if result {
        status_code = 0
    } else {
        status_code = 1
    }
}
