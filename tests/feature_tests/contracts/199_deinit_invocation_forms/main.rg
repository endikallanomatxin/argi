drops :: Int32 = 0

Owner := (.value: Int32)

observe := (.self: $&Owner) -> () { drops = drops + self&.value }

implement Deinit#(Owner) (.deinit = observe)

InlineOwner := (.value: Int32)

implement Deinit#(InlineOwner) (
    .deinit = (.self: $&InlineOwner) -> () { drops = drops + 1 }
)

create_inline_automatic := () -> () { value ::= InlineOwner(42) }

create_inline_explicit := () -> () {
    value ::= InlineOwner(42)
    deinit($&value)
}

create_automatic := () -> () { value ::= Owner(1) }

create_explicit := () -> () {
    value ::= Owner(1)
    deinit($&value)
}

create_alias := () -> () {
    value ::= Owner(1)
    observe($&value)
    if value.value != 1 { abort }
}

main := () -> (.status_code: Int32 = 0) {
    create_inline_automatic()
    if drops != 1 { abort }
    drops = 0
    create_inline_explicit()
    if drops != 1 { abort }
    drops = 0
    create_automatic()
    if drops != 1 { abort }
    drops = 0
    create_explicit()
    if drops != 1 { abort }
    drops = 0
    create_alias()
    if drops != 2 { abort }
}
