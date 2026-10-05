-- Restore a max heap whose children below root are already heaps.
_sift_down#(
        .t : Type: ImplicitlyCopyable
    )(
        .self  : $&IndexableMutable#(.t: t),
        .order : &OrderPolicy#(.t: t),
        .start : UIntNative,
        .count : UIntNative,
    ) -> () := {
    root ::= start
    -- This guard proves that 2 * root + 1 is an existing child and that
    -- child arithmetic cannot overflow, even at the maximum native length.
    while root < count / 2 {
        child ::= root * 2 + 1
        if child + 1 < count {
            left ::= unwrap_or_abort(.value = get_ro_ref(.self = self, .index = child))&
            right ::= unwrap_or_abort(.value = get_ro_ref(.self = self, .index = child + 1))&
            if less(.self = order, .left = left, .right = right).ok { child = child + 1 }
        }
        parent ::= unwrap_or_abort(.value = get_ro_ref(.self = self, .index = root))&
        candidate ::= unwrap_or_abort(.value = get_ro_ref(.self = self, .index = child))&
        if less(.self = order, .left = parent, .right = candidate).ok == false { return }
        _swap_indexed_values#(.t: t)(.self = self, .left = root, .right = child)
        root = child
    }
}

-- Iterative heapsort uses constant auxiliary space and never resizes storage.
-- Policy-equivalent elements can change relative order.
sort#(
        .t : Type: ImplicitlyCopyable
    )(
        .self  : $&IndexableMutable#(.t: t),
        .order : &OrderPolicy#(.t: t),
    ) -> () := {
    count ::= length(self).count

    if count < 2 { return }
    parent ::= count / 2

    while parent > 0 {
        parent = parent - 1
        _sift_down#(.t: t)(.self = self, .order = order, .start = parent, .count = count)
    }

    end ::= count

    while end > 1 {
        end = end - 1
        _swap_indexed_values#(.t: t)(.self = self, .left = 0, .right = end)
        _sift_down#(.t: t)(.self = self, .order = order, .start = 0, .count = end)
    }
}
