Child := (.value: Int32, .reference: &Int32)

Owner := (.child: Child)

reset_child := (.self: $&Child) -> () { self&= (.value = 0, .reference = self&.reference) }

implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () { reset_child(.self = $&self&.child) }
)

create := (.reference: &Int32) -> () {
    owner ::= Owner(.child = (.value = 42, .reference = reference))
}

main := () -> (.status_code: Int32 = 0) {
    value :: Int32 = 7
    create(.reference = &value)
}
