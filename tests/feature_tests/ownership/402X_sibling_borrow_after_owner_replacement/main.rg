Owner := (.number: Int32)

implement Deinit#(Owner) (.deinit = (.self: $&Owner) -> () {})

Record := (.owner: Owner, .borrowed: ?&Int32)

borrow := (.record: $&Record) -> () {
    record&.borrowed = ..some(.value = &record&.owner.number)
}

replace_owner := (.record: $&Record) -> () {
    record&.owner = Owner(2)
}

main := () -> (.status_code: Int32 = 0) {
    record ::= Record(.owner = Owner(1), .borrowed = ..none)
    borrow($&record)
    replace_owner($&record)
    match record.borrowed {
        ..none { abort }
        ..some reference { status_code = reference.value& }
    }
}
