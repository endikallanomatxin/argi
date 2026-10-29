..invalid_multiple

-- Multiples may be any positive integer, including non-powers of two.
round_down := #(.t: Type: UInt) (
    .value: t, .multiple: t, .error_tracer: $&Virtual#(ErrorTracer)
) -> (.result: Errable#(t, (..invalid_multiple))) {
    assume error_tracer

    if multiple == 0 {
        result = ..error(.reason = ..invalid_multiple)
        return
    }

    result = ..ok value - value % multiple
}

round_up := #(.t: Type: UInt) (.value: t, .multiple: t, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(t, (..invalid_multiple, ..out_of_range))
) {
    assume error_tracer

    if multiple == 0 {
        result = ..error(.reason = ..invalid_multiple)
        return
    }

    remainder ::= value % multiple

    if remainder == 0 {
        result = ..ok value
        return
    }

    result = ..ok checked_add#(.t: t)(.left = value, .right = multiple - remainder)!
}
