Range#(.t: Type) : Type = (
    .start: t
    .end: t
    .step: t
)

RangeIterator#(.t: Type) : Type = (
    .current: t
    .end: t
    .step: t
)

Iterable#(.t: Type) canbe Range#(.t: t)
Iterator#(.t: Type) canbe RangeIterator#(.t: t)

init#(.t: Type)(
    .p: $&Range#(.t: t),
    .end: t,
) -> () := {
    zero : t = 0
    one : t = 1
    init#(.t: t)(.p = p, .start = zero, .end = end, .step = one)
}

init#(.t: Type)(
    .p: $&Range#(.t: t),
    .end: t,
    .step: t,
) -> () := {
    zero : t = 0
    init#(.t: t)(.p = p, .start = zero, .end = end, .step = step)
}

init#(.t: Type)(
    .p: $&Range#(.t: t),
    .start: t,
    .end: t,
) -> () := {
    one : t = 1
    init#(.t: t)(.p = p, .start = start, .end = end, .step = one)
}

init#(.t: Type)(
    .p: $&Range#(.t: t),
    .start: t,
    .end: t,
    .step: t,
) -> () := {
    p& = (
        .start = start,
        .end = end,
        .step = step,
    )
}

to_iterator#(.t: Type)(.value: &Range#(.t: t)) -> (.iterator: RangeIterator#(.t: t)) := {
    iterator = (
        .current = value&.start,
        .end = value&.end,
        .step = value&.step,
    )
}

has_next#(.t: Type)(.self: &RangeIterator#(.t: t)) -> (.ok: Bool) := {
    iterator :: RangeIterator#(.t: t) = self&
    zero : t = 0

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

next#(.t: Type)(.self: $&RangeIterator#(.t: t)) -> (.value: t) := {
    iterator :: RangeIterator#(.t: t) = self&
    value = iterator.current
    self& = (
        .current = iterator.current + iterator.step,
        .end = iterator.end,
        .step = iterator.step,
    )
}
