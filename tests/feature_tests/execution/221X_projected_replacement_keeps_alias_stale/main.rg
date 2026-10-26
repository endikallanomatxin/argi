Resource := (.value: Int32)

Holder := (.item: Resource, .sibling: Resource)

implement Deinit<Resource> (.deinit = (.self: $&Resource) -> () {})

replace_field := (.args: (.holder: $&Holder)) -> () {
    args.holder&.item = Resource(.value = 9)
}

main := () -> (.status_code: Int32) {
    holder :: Holder = (.item = Resource(.value = 1), .sibling = Resource(.value = 2))
    previous ::= &holder.item
    replace_field(.args = (.holder = $&holder))
    status_code = previous&.value
}
