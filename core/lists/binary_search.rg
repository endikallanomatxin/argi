-- Search an ordered collection for the first policy-equivalent element.
-- The half-open interval keeps midpoint arithmetic within UIntNative bounds.
binary_search#(
        .t : Type: ImplicitlyCopyable
    )(
        .self  : &Indexable#(.t: t),
        .value : t,
        .order : &OrderPolicy#(.t: t),
    ) -> (
        .index : ?UIntNative
    ) := {
    count ::= length(self).count
    start :: UIntNative = 0
    end ::= count

    while start < end {
        remaining ::= end - start
        middle ::= start + remaining / 2
        element ::= unwrap_or_abort(.value = get_ro_ref(self, .index = middle))&
        if less(order, .left = element, .right = value).ok {
            start = middle + 1
        } else {
            end = middle
        }
    }

    if start < count {
        element ::= unwrap_or_abort(.value = get_ro_ref(self, .index = start))&
        if less(order, .left = value, .right = element).ok == false {
            index = ..some(.value = start)
            return
        }
    }

    index = ..none
}
