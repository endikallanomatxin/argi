Base: Type = (..beta, ..shared)

Extra: Type = (..alpha, ..shared)

Combined: Type = choice_union#(.a: Base, .b: Extra)

source := (
    .shared       : Bool,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(Void, Base)) {
    assume error_tracer

    if shared {
        result = ..error(.reason = ..shared)
    } else {
        result = ..error(.reason = ..beta)
    }
}

extra := (
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(Void, Extra)) {
    assume error_tracer

    result = ..error(.reason = ..alpha)
}

combined := (
    .which        : UInt8,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(Void, Combined)) {
    assume error_tracer

    if which == 0 {
        source(.shared = false)!
    } else if which == 1 {
        source(.shared = true)!
    } else {
        extra()!
    }
    result = ..ok Void()
}

check := (.which: UInt8) -> (.ok: Bool = false) {
    match combined(.which = which) {
        ..ok _ {}
        ..error error {
            match error.reason {
                ..alpha { ok = which == 2 }
                ..beta { ok = which == 0 }
                ..shared { ok = which == 1 }
            }
        }
    }
}

main := () -> (.status_code: Int32 = 0) {
    if check(.which = 0).ok == false { status_code = 1 }
    if check(.which = 1).ok == false { status_code = 2 }
    if check(.which = 2).ok == false { status_code = 3 }
}
