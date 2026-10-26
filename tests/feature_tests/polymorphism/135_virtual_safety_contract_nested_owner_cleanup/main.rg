..failed

Factory<.Participant: Type>: Contract = (
    .make : (.self: &Participant, .mode: Int32) -> (.result: Errable<?Owned, (..failed)>) where {
        on result ..ok {
            on result ..some { owns(result) }
            on result ..none {}
        }
        on result ..error { depends_on(result, error_tracer) }
    }
)

Cell := (.unused: Int32)

implement Factory<Cell> (.make = _impl_make_Cell)

Owned := (.value: Int32)

implement Deinit<Owned> (
    .deinit = (.self: $&Owned) -> () {
        drops = drops + 1
    }
)

drops :: Int32 = 0

_impl_make_Cell := (.self: &Cell, .mode: Int32) -> (.result: Errable<?Owned, (..failed)>) {
    if mode == 0 {
        result = ..ok ..none
        return
    }
    if mode == 1 {
        result = ..ok ..some(.value = Owned(42))
        return
    }

    result = ..error(.reason = ..failed)
}

main := () -> (.status_code: Int32 = 0) {
    cell ::= Cell(0)
    factory ::= to_virtual<Factory>(&cell)

    if true {
        result ::= make(&factory, 0)
    }
    if drops != 0 { status_code = 1 }

    if true {
        result ::= make(&factory, 1)
        match result {
            ..ok ~optional {
                match optional {
                    ..some ~item { if item.value.value != 42 { status_code = 2 } }
                    ..none { status_code = 3 }
                }
            }
            ..error _ { status_code = 4 }
        }
    }
    if drops != 1 { status_code = 5 }

    if true {
        result ::= make(&factory, 2)
    }
    if drops != 1 { status_code = 6 }

    if true {
        result ::= make(&factory, 1)
    }
    if drops != 2 { status_code = 7 }
}
