Value : Type = (.number: Int32)

deinit(.self: $&Value) -> () := {}

replace(.target: $&Value) -> () := {
    target& = (.number = 9)
}

main() -> (.status_code: Int32 = 0) := {
    source :: Value = (.number = 7)
    a ::= $&source
    b ::= $&source

    deinit(.self = a)
    replace(.target = b)

    if b&.number != 9 {
        status_code = 1
        return
    }
    status_code = a&.number
}
