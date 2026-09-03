Value : Type = (
    .number: Int32
)

main() -> (.status_code: Int32 = 0) := {
    source :: Value = (.number = 7)
    a ::= $&source
    b ::= $&source

    b& = (.number = 9)
    if a&.number != 9 {
        status_code = 1
        return
    }
    status_code = 0
}
