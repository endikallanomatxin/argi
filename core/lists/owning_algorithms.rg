-- Comparisons borrow elements so ordering never consumes their resources.
BorrowedOrderPolicy#(.t: Type): Abstract = (
    less(.self: &Self, .left: &t, .right: &t) -> (.ok: Bool)
)

-- Exchange occupied slots through temporary lexical owners. No element is
-- copied or dropped; collection shape invalidation ends pre-existing loans.
_swap_owned_array#(
        .t : Type
    )(
        .self  : $&DynamicArray#(.t: t),
        .left  : UIntNative,
        .right : UIntNative
    ) -> () := {
    if left == right { return }
    if left >= self&._length or right >= self&._length { abort }
    a ::= _trusted_uninit_slot#(.t: t)(.allocation = &self&._allocation, .index = left)
    b ::= _trusted_uninit_slot#(.t: t)(.allocation = &self&._allocation, .index = right)
    first ::= ~_trusted_uninit_take#(.t: t)(.allocation = $&self&._allocation, .slot = a)
    second ::= ~_trusted_uninit_take#(.t: t)(.allocation = $&self&._allocation, .slot = b)
    _trusted_uninit_write#(.t: t)(.allocation = $&self&._allocation, .slot = a, .value = ~second)
    _trusted_uninit_write#(.t: t)(.allocation = $&self&._allocation, .slot = b, .value = ~first)
    _invalidate_dynamic_array_shape#(.t: t)(.array = self)
}

reverse_owned#(.t: Type)(.self: $&DynamicArray#(.t: t)) -> () := {
    left :: UIntNative = 0
    end ::= length(self).count

    while left < end {
        end = end - 1
        if left >= end { return }
        _swap_owned_array#(.t: t)(.self = self, .left = left, .right = end)
        left = left + 1
    }
}

_owned_array_less#(
        .t : Type
    )(
        .self  : &DynamicArray#(.t: t),
        .order : &BorrowedOrderPolicy#(.t: t),
        .left  : UIntNative,
        .right : UIntNative
    ) -> (
        .ok : Bool
    ) := {
    a ::= _trusted_dynamic_array_get_ro_ref#(.t: t)(.array = self, .index = left).reference
    b ::= _trusted_dynamic_array_get_ro_ref#(.t: t)(.array = self, .index = right).reference
    ok = less(.self = order, .left = a, .right = b).ok
}

_owned_sift_down#(
        .t : Type
    )(
        .self  : $&DynamicArray#(.t: t),
        .order : &BorrowedOrderPolicy#(.t: t),
        .start : UIntNative,
        .count : UIntNative
    ) -> () := {
    root ::= start

    while root < count / 2 {
        child ::= root * 2 + 1
        if child + 1 < count {
            if _owned_array_less#(.t: t)(
                .self  = self
                .order = order
                .left  = child
                .right = [
                    child
                    + 1
                ]
            ).ok { child = [
                    child
                    + 1
                ] }
        }
        if [
            _owned_array_less#(.t: t)(.self = self, .order = order, .left = root, .right = child).ok
            == false
        ] { return }
        _swap_owned_array#(.t: t)(.self = self, .left = root, .right = child)
        root = child
    }
}

-- Unstable heapsort uses O(1) auxiliary space and performs no allocation.
sort_owned#(.t: Type)(.self: $&DynamicArray#(.t: t), .order: &BorrowedOrderPolicy#(.t: t)) -> () := {
    count ::= length(self).count
    parent ::= count / 2

    while parent > 0 {
        parent = parent - 1
        _owned_sift_down#(.t: t)(.self = self, .order = order, .start = parent, .count = count)
    }

    end ::= count

    while end > 1 {
        end = end - 1
        _swap_owned_array#(.t: t)(.self = self, .left = 0, .right = end)
        _owned_sift_down#(.t: t)(.self = self, .order = order, .start = 0, .count = end)
    }
}
