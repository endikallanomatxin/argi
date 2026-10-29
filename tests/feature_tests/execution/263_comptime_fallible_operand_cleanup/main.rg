..stop

Counter := (.drops: Int32 = 0)

Resource := (.counter: $&Counter, .id: Int32)

Choice: Type = (..pair(.left: Resource, .right: Resource), ..empty)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        self&.counter&.drops = self&.counter&.drops + self&.id
    }
)

maybe_resource := (
    .counter      : $&Counter,
    .fail         : Bool,
    .tracer       : $&Virtual#(ErrorTracer),
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Resource, (..stop))) {
    assume error_tracer

    if fail {
        result = ..error(.reason = ..stop, .tracer = tracer)
    } else {
        result = ..ok Resource(.counter = counter, .id = 14)
    }
}

build_owned := (
    .counter      : $&Counter,
    .fail         : Bool,
    .tracer       : $&Virtual#(ErrorTracer),
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Choice, (..stop))) {
    assume error_tracer

    value :: Choice = ..pair(
        .left  = Resource(.counter = counter, .id = 7)
        .right = maybe_resource(.counter = counter, .fail = fail, .tracer = tracer)!
    )
    result = ..ok ~value
}

discard_result := (.value: Errable#(Choice, (..stop))) -> () { owner ::= ~value }

consume_pair := (.left: Resource, .right: Resource) -> (.result: Int32) {
    first ::= ~left
    second ::= ~right
    result = 42
}

build_call := (
    .counter      : $&Counter,
    .fail         : Bool,
    .tracer       : $&Virtual#(ErrorTracer),
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Int32, (..stop))) {
    assume error_tracer

    result = ..ok consume_pair(
        .left  = Resource(.counter = counter, .id = 7)
        .right = maybe_resource(.counter = counter, .fail = fail, .tracer = tracer)!
    )
}

build_array := (
    .counter      : $&Counter,
    .fail         : Bool,
    .tracer       : $&Virtual#(ErrorTracer),
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Int32, (..stop))) {
    assume error_tracer

    values :: [2]Resource = (
        Resource(.counter = counter, .id = 7),
        maybe_resource(.counter = counter, .fail = fail, .tracer = tracer)!
    )
    result = ..ok 42
}

State: Type = ()

Consumer#(.StateType: Type): Contract = (
    .consume : (.self: $&StateType, .left: Resource, .right: Resource) -> (.result: Int32) where {}
)

implement Consumer#(State) (
    .consume = (.self: $&State, .left: Resource, .right: Resource) -> (.result: Int32) {
        first ::= ~left
        second ::= ~right
        result = 42
    }
)

build_virtual := (
    .handle       : $&Virtual#(Consumer),
    .counter      : $&Counter,
    .fail         : Bool,
    .tracer       : $&Virtual#(ErrorTracer),
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Int32, (..stop))) {
    assume error_tracer

    result = ..ok Consumer#(
    ).consume(
        .self  = handle
        .left  = Resource(.counter = counter, .id = 7)
        .right = maybe_resource(.counter = counter, .fail = fail, .tracer = tracer)!
    )
}

probe := () -> (.result: Int32) {
    counter :: Counter = Counter()
    tracer :: NoopErrorTracer = (.marker = 0)
    erased ::= to_virtual#(.contract: ErrorTracer)(.value = $&tracer)
    assume error_tracer ::= $&erased
    failed ::= build_owned(.counter = $&counter, .fail = true, .tracer = $&erased)
    if counter.drops != 7 { abort }
    succeeded ::= build_owned(.counter = $&counter, .fail = false, .tracer = $&erased)
    if counter.drops != 7 { abort }
    discard_result(.value = ~succeeded)
    failed_array ::= build_array(.counter = $&counter, .fail = true, .tracer = $&erased)
    if counter.drops != 35 { abort }
    succeeded_array ::= build_array(.counter = $&counter, .fail = false, .tracer = $&erased)
    if counter.drops != 56 { abort }
    failed_call ::= build_call(.counter = $&counter, .fail = true, .tracer = $&erased)
    if counter.drops != 63 { abort }
    succeeded_call ::= build_call(.counter = $&counter, .fail = false, .tracer = $&erased)
    if counter.drops != 84 { abort }
    state :: State = ()
    handle ::= to_virtual#(.contract: Consumer)(.value = $&state)
    failed_virtual ::= build_virtual(
        .handle = $&handle, .counter = $&counter, .fail = true, .tracer = $&erased
    )
    if counter.drops != 91 { abort }
    succeeded_virtual ::= build_virtual(
        .handle = $&handle, .counter = $&counter, .fail = false, .tracer = $&erased
    )
    result = counter.drops
}

main := () -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    if #run () -> (.value: Int32) { value = probe() } != 112 { abort }
    if probe() != 112 { abort }
    status_code = 42
}
