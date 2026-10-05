..bit_set_size_mismatch

-- Byte-local arithmetic avoids changing the representation or operand width.
-- Modes are private: zero union, one intersection, two difference.
_bit_set_combine(.left: UInt8, .right: UInt8, .mode: UInt8) -> (.value: UInt8 = 0) := {
    a ::= left
    b ::= right
    place :: UInt8 = 1
    index :: UIntNative = 0

    while index < 8 {
        keep ::= false
        if mode == 0 { keep = a % 2 != 0 or b % 2 != 0 }
        if mode == 1 { keep = a % 2 != 0 and b % 2 != 0 }
        if mode == 2 { keep = a % 2 != 0 and b % 2 == 0 }
        if keep { value = value + place }
        a = a / 2
        b = b / 2
        index = index + 1
        if index < 8 { place = place * 2 }
    }
}

_bit_set_combine_into(
        .self  : $&BitSet,
        .other : &BitSet,
        .mode  : UInt8
    ) -> (
        .result : Errable#(Void, (..bit_set_size_mismatch)) = ..ok Void()
    ) := {
    if self&._count != other&._count {
        result = ..error(.reason = ..bit_set_size_mismatch)
        return
    }

    index :: UIntNative = 0

    while index < length(&self&._storage).count {
        left ::= unwrap_or_abort(.value = get_rw_ref($&self&._storage, .index = index))
        right ::= unwrap_or_abort(.value = get_ro_ref(&other&._storage, .index = index))
        left&= _bit_set_combine(.left = left&, .right = right&, .mode = mode).value
        index = index + 1
    }
}

union_with(
        .self  : $&BitSet,
        .other : &BitSet
    ) -> (
        .result : Errable#(Void, (..bit_set_size_mismatch))
    ) := {
    result = _bit_set_combine_into(self, .other = other, .mode = 0)
}

intersect_with(
        .self  : $&BitSet,
        .other : &BitSet
    ) -> (
        .result : Errable#(Void, (..bit_set_size_mismatch))
    ) := {
    result = _bit_set_combine_into(self, .other = other, .mode = 1)
}

difference_with(
        .self  : $&BitSet,
        .other : &BitSet
    ) -> (
        .result : Errable#(Void, (..bit_set_size_mismatch))
    ) := {
    result = _bit_set_combine_into(self, .other = other, .mode = 2)
}
