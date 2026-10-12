Range#(.t: Type): Type = (
    .start : t
    .end   : t
    .step  : t
)

RangeIterator#(.t: Type): Type = (
    .current : t
    .end     : t
    .step    : t
)

Range init#(
        .t : Type
    )(
        .end : t,
    ) -> (
        .result : Range#(.t: t)
    ) := {
    zero: t = 0
    one: t = 1

    result = Range#(.t: t)(.start = zero, .end = end, .step = one)
}

Range init#(
        .t : Type
    )(
        .end  : t,
        .step : t,
    ) -> (
        .result : Range#(.t: t)
    ) := {
    zero: t = 0

    result = Range#(.t: t)(.start = zero, .end = end, .step = step)
}

Range init#(
        .t : Type
    )(
        .start : t,
        .end   : t,
    ) -> (
        .result : Range#(.t: t)
    ) := {
    one: t = 1

    result = Range#(.t: t)(.start = start, .end = end, .step = one)
}

Range init#(
        .t : Type
    )(
        .start : t,
        .end   : t,
        .step  : t,
    ) -> (
        .result : Range#(.t: t)
    ) := {
    result = (
        .start = start
        .end   = end
        .step  = step
    )
}

implement#(.t: Type) Iterable#(Range#(.t: t)) (
    .Item: Type = t
    .IteratorType: Type = RangeIterator#(.t: t)

    .to_iterator = (.value: &Range#(.t: t)) -> (.iterator: RangeIterator#(.t: t)) {
        iterator = (
            .current = value&.start
            .end     = value&.end
            .step    = value&.step
        )
    }
)

implement#(.t: Type) Iterator#(RangeIterator#(.t: t)) (
    .Item: Type = t

    .has_next = (.self: &RangeIterator#(.t: t)) -> (.ok: Bool) {
        iterator :: RangeIterator#(.t: t) = self&
        zero: t = 0

        if iterator.step > zero {
            ok = iterator.current < iterator.end
            return
        }

        if iterator.step < zero {
            ok = iterator.current > iterator.end
            return
        }

        ok = 0 == 1
    }

    .next = (.self: $&RangeIterator#(.t: t)) -> (.value: t) {
        iterator :: RangeIterator#(.t: t) = self&
        value = iterator.current
        self&= (
            .current = iterator.current + iterator.step
            .end     = iterator.end
            .step    = iterator.step
        )
    }
)
