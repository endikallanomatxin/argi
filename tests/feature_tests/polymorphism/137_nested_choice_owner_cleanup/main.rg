..failed

Cell := (.unused: Int32)

Owned := (.value: Int32)

implement Deinit#(Owned) (
    .deinit = (.self: $&Owned) -> () {
        drops = drops + 1
    }
)

drops :: Int32 = 0

make := (.self: &Cell, .mode: Int32, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(?Owned, (..failed))
) {
    assume error_tracer

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

Envelope := (.result: Errable#(?Owned, (..failed)))

leave_early := (.cell: &Cell, .error_tracer: $&Virtual#(ErrorTracer)) -> () {
    assume error_tracer
    result ::= make(cell, 1)
    return
}

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    cell ::= Cell(0)

    if true {
        result ::= make(&cell, 0)
    }
    if drops != 0 { status_code = 1 }

    if true {
        result ::= make(&cell, 1)
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
        result ::= make(&cell, 2)
    }
    if drops != 1 { status_code = 6 }

    if true {
        result ::= make(&cell, 1)
    }
    if drops != 2 { status_code = 7 }

    leave_early(&cell)
    if drops != 3 { status_code = 8 }

    if true {
        envelope ::= Envelope(make(&cell, 1))
    }
    if drops != 4 { status_code = 9 }

    if true {
        original ::= make(&cell, 1)
        moved ::= ~original
    }
    if drops != 5 { status_code = 10 }

}
