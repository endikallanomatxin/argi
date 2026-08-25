Resource : Type = (
    .value: Int32
)

deinit(.self: $&Resource) -> () #invalidates(self) := {}

main() -> (.status_code: Int32) := {
    resource :: Resource = (.value = 1)
    pointer := $&resource.value
    moved ::= ~resource
    moved.value = 2

    if pointer& != 2 {
        status_code = 1
        return
    }

    deinit(.self = $&moved)
    status_code = 0
}
