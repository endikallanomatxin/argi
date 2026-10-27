Counter := (.drops: Int32 = 0, .selections: Int32 = 0)

Resource := (.counter: $&Counter, .value: Int32)

Holder := (.reference: $&Resource)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.drops = self&.counter&.drops + 1
    }
)

retarget_first := (.holder: $&Holder, .other: $&Resource, .counter: $&Counter) -> () {
    holder&.reference = other
    holder&.reference&= Resource(.counter = counter, .value = 9)
}

retarget_wrapped := (.counter: $&Counter, .other: $&Resource, .holder: $&Holder) -> () {
    retarget_first(.holder = holder, .other = other, .counter = counter)
}

main := () -> (.status_code: Int32) {
    counter :: Counter = Counter()
    {
        owner :: Resource = Resource(.counter = $&counter, .value = 1)
        other :: Resource = Resource(.counter = $&counter, .value = 2)
        holder :: Holder = Holder(.reference = $&owner)
        preserved ::= $&owner
        retarget_wrapped(.counter = $&counter, .other = $&other, .holder = $&holder)
        if preserved&.value != 1 or other.value != 9 or holder.reference&.value != 9 { abort }
        if counter.drops != 1 { abort }
    }
    if counter.drops != 3 { abort }
    status_code = 42
}
