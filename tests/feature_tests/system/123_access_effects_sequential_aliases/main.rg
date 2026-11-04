Box := (.reference: $&Int32)
write := (.box: Box) -> () { box.reference& = 21 }
read := (.value: &Int32) -> (.result: Int32) { result = value& }
main := () -> (.status_code: Int32) {
    value :: Int32 = 0
    a ::= $&value
    b ::= $&value
    box: Box = (.reference = a)
    write(.box = box)
    b& = b& * 2
    status_code = read(.value = &value)
}
