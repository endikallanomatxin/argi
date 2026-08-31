Value : Type = (.number: Int32)

write(.target: $&Value) -> () := {
    target& = (.number = 9)
}

main() -> (.status_code: Int32 = 0) := {
    source :: Value = (.number = 7)
    a ::= $&source
    b ::= $&source

    write(.target = b)
    if a&.number != 9 or b&.number != 9 {
        status_code = 1
        return
    }
    status_code = 0
}
