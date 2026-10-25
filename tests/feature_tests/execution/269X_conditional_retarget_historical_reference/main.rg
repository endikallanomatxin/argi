Counter: Type = (.drops: Int32 = 0, .selections: Int32 = 0)

Resource: Type = (.counter: $&Counter, .value: Int32)

Holder: Type = (.reference: $&Resource)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.drops = self&.counter&.drops + 1
    }
)

retarget_first(.holder: $&Holder, .other: $&Resource, .counter: $&Counter) -> () := {
    if counter&.selections == 0 { holder&.reference = other }
    holder&.reference&= Resource(.counter = counter, .value = 9)
}

main() -> (.status_code: Int32) := {
    counter :: Counter = Counter()
    owner :: Resource = Resource(.counter = $&counter, .value = 1)
    other :: Resource = Resource(.counter = $&counter, .value = 2)
    holder :: Holder = Holder(.reference = $&owner)
    historical ::= $&other
    retarget_first(.holder = $&holder, .other = $&other, .counter = $&counter)
    status_code = historical&.value
}
