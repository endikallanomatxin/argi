Counter: Type = (.count: Int32 = 0)

Owner: Type = (.counter: $&Counter, .value: Int32, .saved: &Int32)

implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () {
        self&.counter&.count = self&.counter&.count + 1
    }
)

Container: Type = (.owner: Owner)

main() -> () := {
    counter :: Counter = Counter()
    external ::= 0
    container :: Container = Container(
        .owner = Owner(.counter = $&counter, .value = 1, .saved = &external)
    )
    container.owner = Owner(.counter = $&counter, .value = 2, .saved = &container.owner.value)
    observed ::= container.owner.saved&
}
