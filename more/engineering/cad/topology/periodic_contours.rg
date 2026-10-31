-- Admission of one traversal of a shared periodic support. Topological endpoint
-- identity is checked separately; chart parameters may differ by whole turns.
-- No temporary storage or persistent connectivity is introduced here.
_admit_periodic_contour := #(.Scalar: Type: Float) (
    .uses: &DynamicArray#(_ResolvedTrim#(Scalar)), .start: UIntNative, .count: UIntNative
) -> (.result: Errable#(Void, BrepErrors)) {
    if count == 0 {
        result = ..error(.reason = ..unsupported_boundary)
        return
    }
    first ::= get(uses, .index = start)!
    current ::= first.interval.start
    if first.reversed { current = first.interval.end }
    covered :: Scalar = 0.0
    i :: UIntNative = 0
    while i < count {
        use ::= get(uses, .index = start + i)!
        if use.curve != first.curve or use.reversed != first.reversed {
            result = ..error(.reason = ..unsupported_boundary)
            return
        }
        begin ::= use.interval.start
        end ::= use.interval.end
        if use.reversed {
            begin = use.interval.end
            end = use.interval.start
        }
        difference ::= begin - current
        if [is_finite(difference).ok == false or difference != floor_float(difference).result] {
            result = ..error(.reason = ..unsupported_parameterization)
            return
        }
        span ::= use.interval.end - use.interval.start
        if is_finite(span).ok == false or span <= 0.0 or span > 1.0 {
            result = ..error(.reason = ..unsupported_parameterization)
            return
        }
        covered = covered + span
        current = end
        i = i + 1
    }
    if covered != 1.0 {
        result = ..error(.reason = ..unsupported_parameterization)
        return
    }
    result = ..ok Void()
}
