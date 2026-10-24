Counter: Type = (.drops: Int32 = 0, .selections: Int32 = 0)

Resource: Type = (.counter: $&Counter, .value: Int32)

Holder: Type = (.reference: $&Resource)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.drops = self&.counter&.drops + 1
    }
)

retarget_first(.holder: $&Holder, .other: $&Resource, .counter: $&Counter) -> () := {
    holder&.reference = other
    holder&.reference&= Resource(.counter = counter, .value = 9)
}

retarget_wrapped(.counter: $&Counter, .other: $&Resource, .holder: $&Holder) -> () := {
    retarget_first(.holder = holder, .other = other, .counter = counter)
}

main() -> (.status_code: Int32) := {
    counter :: Counter = Counter()
    owner :: Resource = Resource(.counter = $&counter, .value = 1)
    other :: Resource = Resource(.counter = $&counter, .value = 2)
    holder :: Holder = Holder(.reference = $&owner)
    historical ::= $&other
    retarget_wrapped(.counter = $&counter, .other = $&other, .holder = $&holder)
    status_code = historical&.value
}
