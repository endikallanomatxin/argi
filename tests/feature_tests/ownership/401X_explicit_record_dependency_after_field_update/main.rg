Owner := (.number: Int32)

implement Deinit#(Owner) (.deinit = (.self: $&Owner) -> () {})

Record := (.left: Int32, .right: Int32)

update := (.record: $&Record) -> () { record&.right = 3 }

read := (.record: Record) -> (.number: Int32) { number = record.left }

main := () -> (.status_code: Int32) {
    owner ::= Owner(7)
    record ::= depend_on#(Record)(.value = Record(1, 2), .on = &owner).result
    update($&record)
    deinit($&owner)
    status_code = read(~record).number
}
