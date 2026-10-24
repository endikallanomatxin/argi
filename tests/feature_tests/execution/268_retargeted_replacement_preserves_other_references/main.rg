..stop

Counter: Type = (.drops: Int32 = 0, .selections: Int32 = 0)

Resource: Type = (.counter: $&Counter, .value: Int32)

Holder: Type = (.reference: $&Resource)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.drops = self&.counter&.drops + 1
    }
)

select_holder(.holder: $&Holder, .counter: $&Counter) -> (.result: $&Holder) := {
    if counter&.selections >= 0 { counter&.selections = counter&.selections + 1 }
    result = holder
}

maybe_retarget(.holder: $&Holder, .other: $&Resource, .counter: $&Counter, .fail: Bool) -> (
    .result : Errable#(Resource, (..stop))
) := {
    holder&.reference = other
    if fail {
        result = ..error(.reason = ..stop)
    } else {
        result = ..ok Resource(.counter = counter, .value = 9)
    }
}

replace(.holder: $&Holder, .other: $&Resource, .counter: $&Counter, .fail: Bool) -> (
    .result : Errable#(Int32, (..stop))
) := {
    [select_holder(.holder = holder, .counter = counter)&.reference]&= maybe_retarget(
        .holder = holder, .other = other, .counter = counter, .fail = fail
    )!
    result = ..ok 42
}

retarget_first(.holder: $&Holder, .other: $&Resource, .counter: $&Counter) -> () := {
    holder&.reference = other
    holder&.reference&= Resource(.counter = counter, .value = 9)
}

retarget_wrapped(.counter: $&Counter, .other: $&Resource, .holder: $&Holder) -> () := {
    retarget_first(.holder = holder, .other = other, .counter = counter)
}

main() -> (.status_code: Int32) := {
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
