drops :: Int32 = 0

Owner := (.value: Int32)

implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () {
        drops = drops + 1
    }
)

implement Init#(Owner) (
    .init = (.value: Int32) -> (.result: Owner) { result = (.value = value) }
)

create := () -> () { value ::= Owner(.value = 42) }

main := () -> (.status_code: Int32 = 0) {
    create()
    if drops != 1 { abort }
}
