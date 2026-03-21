Range : Type = (
    .start: Int32
    .end: Int32
    .step: Int32
)

RangeIterator : Type = (
    .current: Int32
    .end: Int32
    .step: Int32
)

Iterable canbe Range
Iterator canbe RangeIterator

init(
    .p: $&Range,
    .start: Int32,
    .end: Int32,
    .step: Int32,
) -> () := {
    p& = (
        .start = start,
        .end = end,
        .step = step,
    )
}

to_iterator(.value: &Range) -> (.iterator: RangeIterator) := {
    iterator = (
        .current = value&.start,
        .end = value&.end,
        .step = value&.step,
    )
}

has_next(.self: &RangeIterator) -> (.ok: Bool) := {
    iterator :: RangeIterator = self&
    zero :: Int32 = 0

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

next(.self: $&RangeIterator) -> (.value: Int32) := {
    iterator :: RangeIterator = self&
    value = iterator.current
    self& = (
        .current = iterator.current + iterator.step,
        .end = iterator.end,
        .step = iterator.step,
    )
}
