Value : Type = (
    .number: Int32
)

deinit(.self: $&Value) -> () := {
}

main() -> (.status_code: Int32) := {
    source :: Value = (.number = 7)
    pointer ::= $&source
    deinit(.self = pointer)

    pointer& = (.number = 9)
    if source.number != 9 {
        status_code = 1
        return
    }

    deinit(.self = $&source)
    status_code = 0
}
