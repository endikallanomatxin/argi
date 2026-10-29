..stop

Counter := (.drops: Int32 = 0, .selections: Int32 = 0)

Resource := (.counter: $&Counter, .value: Int32)

Holder := (.reference: $&Resource)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.drops = self&.counter&.drops + 1
    }
)

select_holder := (.holder: $&Holder, .counter: $&Counter) -> (.result: $&Holder) {
    if counter&.selections >= 0 { counter&.selections = counter&.selections + 1 }
    result = holder
}

maybe_retarget := (
    .holder       : $&Holder,
    .other        : $&Resource,
    .counter      : $&Counter,
    .fail         : Bool,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Resource, (..stop))) {
    assume error_tracer

    holder&.reference = other
    if fail {
        result = ..error(.reason = ..stop)
    } else {
        result = ..ok Resource(.counter = counter, .value = 9)
    }
}

replace := (
    .holder       : $&Holder,
    .other        : $&Resource,
    .counter      : $&Counter,
    .fail         : Bool,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Int32, (..stop))) {
    assume error_tracer

    [select_holder(.holder = holder, .counter = counter)&.reference]&= maybe_retarget(
        .holder = holder, .other = other, .counter = counter, .fail = fail
    )!
    result = ..ok 42
}

main := () -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    counter :: Counter = Counter()
    {
        owner :: Resource = Resource(.counter = $&counter, .value = 1)
        other :: Resource = Resource(.counter = $&counter, .value = 2)
        holder :: Holder = Holder(.reference = $&owner)
        replace(.holder = $&holder, .other = $&other, .counter = $&counter, .fail = true) handle error {
            match error.reason { ..stop {} }
        }
        if counter.drops != 0 or counter.selections != 1 { abort }
        if owner.value != 1 or holder.reference&.value != 2 { abort }
        holder.reference = $&owner
        historical ::= holder.reference
        replace(.holder = $&holder, .other = $&other, .counter = $&counter, .fail = false) handle error {
            abort
        }
        if counter.drops != 1 or counter.selections != 2 { abort }
        if historical&.value != 9 { abort }
    }
    if counter.drops != 3 { abort }
    status_code = 42
}
