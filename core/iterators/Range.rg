Range := #(.t: Type) (
    .start : t
    .end   : t
    .step  : t
)

RangeIterator := #(.t: Type) (
    .current : t
    .end     : t
    .step    : t
)

RangeInitArgs: Type = #(.t: Type) (.end: t, .start: t = 0, .step: t = 1)

implement#(.t: Type) Init#(Range#(.t: t), RangeInitArgs#(t)) (
    .Result : Type = Range#(.t: t)

    .init = RangeInitArgs#(t) -> (.result: Result) {
        result = (.start = start, .end = end, .step = step)
    }
)

implement#(.t: Type) Iterable#(Range#(.t: t)) (
    .Item         : Type = t
    .IteratorType : Type = RangeIterator#(.t: t)

    .to_iterator = (.value: &Range#(.t: t)) -> (.iterator: RangeIterator#(.t: t)) {
        iterator = (.current = value&.start, .end = value&.end, .step = value&.step)
    }
)

implement#(.t: Type) Iterator#(RangeIterator#(.t: t)) (
    .Item : Type = t

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
