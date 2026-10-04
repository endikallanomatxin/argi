-- Equality search copies only implicitly copyable elements. Returning an
-- index creates no element loan; structural changes can make it stale.
find#(
        .t : Type: ImplicitlyCopyable
    )(
        .self  : &Indexable#(.t: t),
        .value : t,
    ) -> (
        .index : ?UIntNative
    ) := {
    count ::= length(.self = self).count
    position :: UIntNative = 0
    while position < count {
        element ::= unwrap_or_abort(.value = get_ro_ref(.self = self, .index = position))&
        if element == value {
            index = ..some(.value = position)
            return
        }
        position = position + 1
    }
    index = ..none
}

contains#(
        .t : Type: ImplicitlyCopyable
    )(
        .self  : &Indexable#(.t: t),
        .value : t,
    ) -> (
        .ok : Bool
    ) := {
    ok = is(.value = find#(.t: t)(.self = self, .value = value).index, .variant = ..some)
}
