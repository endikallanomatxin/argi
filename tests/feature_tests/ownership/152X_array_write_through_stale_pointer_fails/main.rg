Value : Type = (
    .items: [2]Int32
)

deinit(.self: $&Value) -> () := {
}

main() -> (.status_code: Int32) := {
    source :: Value = (.items = (7, 8))
    stale ::= $&source.items
    deinit(.self = $&source)
    source = (.items = (9, 10))

    stale&[0] = 11
    status_code = 0
    deinit(.self = $&source)
}
