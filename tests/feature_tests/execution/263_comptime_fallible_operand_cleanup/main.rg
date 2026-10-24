..stop

Counter: Type = (.drops: Int32 = 0)

Resource: Type = (.counter: $&Counter, .id: Int32)

Choice: Type = (..pair(.left: Resource, .right: Resource), ..empty)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.drops = self&.counter&.drops + self&.id
    }
)

maybe_resource(.counter: $&Counter, .fail: Bool, .tracer: $&Virtual#(.contract: ErrorTracer)) -> (
    .result : Errable#(Resource, (..stop))
) := {
    if fail {
        result = ..error(.reason = ..stop, .tracer = tracer)
    } else {
        result = ..ok Resource(.counter = counter, .id = 14)
    }
}

build_owned(.counter: $&Counter, .fail: Bool, .tracer: $&Virtual#(.contract: ErrorTracer)) -> (
    .result : Errable#(Choice, (..stop))
) := {
    value :: Choice = ..pair(
        .left  = Resource(.counter = counter, .id = 7)
        .right = maybe_resource(.counter = counter, .fail = fail, .tracer = tracer)!
    )
    result = ..ok ~value
}

discard_result(.value: Errable#(Choice, (..stop))) -> () := { owner ::= ~value }

probe() -> (.result: Int32) := {
    counter :: Counter = Counter()
    tracer :: NoopErrorTracer = (.marker = 0)
    erased ::= to_virtual#(.contract: ErrorTracer)(.value = $&tracer)
    failed ::= build_owned(.counter = $&counter, .fail = true, .tracer = $&erased)
    if counter.drops != 7 { abort }
    succeeded ::= build_owned(.counter = $&counter, .fail = false, .tracer = $&erased)
    if counter.drops != 7 { abort }
    discard_result(.value = ~succeeded)
    result = counter.drops
}

main() -> (.status_code: Int32) := {
    if #run () -> (.value: Int32) { value = probe() } != 28 { abort }
    status_code = probe() + 14
}
