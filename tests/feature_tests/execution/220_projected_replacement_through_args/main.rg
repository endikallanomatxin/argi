drops :: Int32 = 0

Resource := (.value: Int32)

Holder := (.item: Resource, .sibling: Resource)

implement Deinit#(Resource) (.deinit = (.self: $&Resource) -> () { drops = drops + 1 })

replace_field := (.args: (.holder: $&Holder)) -> () {
    args.holder&.item = Resource(.value = 9)
}

replace_element := (.args: (.items: $&[2]Resource)) -> () {
    args.items&[0] = Resource(.value = 8)
}

main := () -> (.status_code: Int32) {
    {
        holder :: Holder = (.item = Resource(.value = 1), .sibling = Resource(.value = 2))
        replace_field(.args = (.holder = $&holder))
        if holder.item.value != 9 or holder.sibling.value != 2 { abort }
    }
    if drops != 3 { abort }
    {
        items :: [2]Resource = (Resource(.value = 3), Resource(.value = 4))
        replace_element(.args = (.items = $&items))
        if items[0].value != 8 or items[1].value != 4 { abort }
    }
    if drops != 6 { abort }
    status_code = 42
}
