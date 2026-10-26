drops :: Int32 = 0

Owner := (.value: Int32)

implement Deinit<Owner> (
    .deinit = (.self: $&Owner) -> () {
        drops = drops + 1
    }
)

implement Init<Owner, (.value: Int32)> (
    .Result : Type = Owner
    .init   = (.args: (.value: Int32)) -> (.result: Result) { result = (.value = args.value) }
)

create := () -> () { value ::= Owner(.value = 42) }

main := () -> (.status_code: Int32 = 0) {
    create()
    if drops != 1 { abort }
}
