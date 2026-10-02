Value : Type = (
    .number: UInt8
)

deinit(.self: $&Value) -> () := {
}

main() -> (.status_code: Int32) := {
    source :: Value = (.number = 7)
    stale ::= &source
    deinit(.self = $&source)
    source = (.number = 9)

    revived ::= &stale&.number
    if revived& == 9 {
        status_code = 0
    } else {
        status_code = 1
    }

    deinit(.self = $&source)
}
