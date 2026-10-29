..failed

Mover#(.Participant: Type): Contract = (
    .transfer : (
        .self         : &Participant,
        .source       : $&Resource,
        .destination  : $&Resource,
        .move         : Bool,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(?Int32, (..failed))) where {
        on result ..ok {
            on result ..some { relocates(destination, source) }
            on result ..none {}
        }
        on result ..error { depends_on(result, error_tracer) }
    }
)

Manager := (.unused: Int32)

implement Mover#(Manager) (.transfer = _impl_transfer_Manager)

Resource := (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        drops = drops + 1
    }
)

drops :: Int32 = 0

_impl_transfer_Manager := (
    .self         : &Manager,
    .source       : $&Resource,
    .destination  : $&Resource,
    .move         : Bool,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(?Int32, (..failed))) {
    assume error_tracer

    if move {
        relocate(source, destination)
        result = ..ok ..some(.value = 1)
        return
    }

    result = ..ok ..none
}

transfer_owned := (
    .mover        : &Virtual#(Mover),
    .source       : $&Resource,
    .destination  : $&Resource,
    .move         : Bool,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(?Int32, (..failed))) {
    assume error_tracer

    result = transfer(mover, source, destination, move)
}

main := () -> (.status_code: Int32 = 0) {
    manager ::= Manager(0)
    mover ::= to_virtual#(Mover)(&manager)

    if true {
        source ::= Resource(42)
        destination ::= Resource(0)
        deinit($&destination)
        outcome ::= transfer_owned(&mover, $&source, $&destination, true)

        match outcome {
            ..ok ~optional {
                match optional {
                    ..some _ { if destination.value != 42 { status_code = 1 } }
                    ..none { status_code = 2 }
                }
            }
            ..error _ { status_code = 3 }
        }
    }
    if drops != 2 { status_code = 4 }

    if true {
        source ::= Resource(43)
        destination ::= Resource(0)
        deinit($&destination)
        outcome ::= transfer_owned(&mover, $&source, $&destination, false)

        match outcome {
            ..ok ~optional {
                match optional {
                    ..some _ { status_code = 5 }
                    ..none { if source.value != 43 { status_code = 6 } }
                }
            }
            ..error _ { status_code = 7 }
        }
    }
    if drops != 4 { status_code = 8 }

    if true {
        source ::= Resource(44)
        destination ::= Resource(0)
        deinit($&destination)
        transfer_owned(&mover, $&source, $&destination, true)
    }
    if drops != 6 { status_code = 9 }
}
