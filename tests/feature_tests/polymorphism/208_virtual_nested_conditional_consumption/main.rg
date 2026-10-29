..failed

Releaser#(.Participant: Type): Contract = (
    .release : (
        .self         : &Participant,
        .resource     : $&Resource,
        .mode         : Int32,
        .error_tracer : $&Virtual#(ErrorTracer)
    ) -> (.result: Errable#(?Int32, (..failed))) where {
        on result ..ok {
            on result ..some { consumes(resource) }
            on result ..none {}
        }
        on result ..error { depends_on(result, error_tracer) }
    }
)

Resource := (.value: Int32)

Manager := (.unused: Int32)

implement Releaser#(Manager) (.release = _impl_release_Manager)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        drops = drops + 1
    }
)

drops :: Int32 = 0

_impl_release_Manager := (
    .self: &Manager, .resource: $&Resource, .mode: Int32, .error_tracer: $&Virtual#(ErrorTracer)
) -> (.result: Errable#(?Int32, (..failed))) {
    assume error_tracer

    if mode == 2 {
        result = ..error(.reason = ..failed)
        return
    }
    if mode == 1 {
        deinit(resource)
        result = ..ok ..some(.value = 42)
        return
    }

    result = ..ok ..none
}

release_again := (
    .releaser     : &Virtual#(Releaser),
    .resource     : $&Resource,
    .mode         : Int32,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(?Int32, (..failed))) {
    assume error_tracer

    result = release(releaser, resource, mode)
}

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    manager ::= Manager(0)
    releaser ::= to_virtual#(Releaser)(&manager)

    if true {
        resource ::= Resource(42)
        result ::= release_again(&releaser, $&resource, 0)

        match result {
            ..ok ~optional {
                match optional {
                    ..none { if resource.value != 42 { status_code = 1 } }
                    ..some _ { status_code = 2 }
                }
            }
            ..error _ { status_code = 3 }
        }
    }
    if drops != 1 { status_code = 4 }

    if true {
        resource ::= Resource(43)
        release_again(&releaser, $&resource, 1)
    }
    if drops != 2 { status_code = 5 }

    if true {
        resource ::= Resource(44)
        result ::= release_again(&releaser, $&resource, 2)

        match result {
            ..error _ { if resource.value != 44 { status_code = 6 } }
            ..ok ~_ { status_code = 7 }
        }
    }
    if drops != 3 { status_code = 8 }
}
