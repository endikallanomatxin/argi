drops :: Int32 = 0

Owner := (.value: Int32)

implement Deinit<Owner> (.deinit = (.self: $&Owner) -> () { drops = drops + 1 })

implement Init<Owner, (.value: Int32)> (
    .Result : Type = Owner
    .init   = (.args: (.value: Int32)) -> (.result: Result) { result = (.value = args.value) }
)

Pair := (.first: Owner, .second: Owner)

Choice: Type = (..none, ..some(.pair: Pair))

create := () -> () {
    value :: Choice = ..some(.pair = (.first = Owner(1), .second = Owner(2)))
    match value {
        ..none {}
        ..some ~payload { moved ::= ~payload.pair }
    }
}

main := () -> (.status_code: Int32 = 0) {
    create()
    if drops != 2 { abort }
}
