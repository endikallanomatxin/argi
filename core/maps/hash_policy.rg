-- Equal keys must have equal hashes. Both operations must remain stable while
-- keys are stored; borrowed key bytes must remain live and unchanged.
HashPolicy#(.key: Type: ImplicitlyCopyable): Abstract = (
    hash(.self: &Self, .key: key) -> (.hash: UIntNative)
    eql(.self: &Self, .left: key, .right: key) -> (.ok: Bool)
)

UIntNativeHashPolicy: Type = ()

UIntNativeHashPolicy implements ImplicitlyCopyable
UIntNativeHashPolicy implements HashPolicy#(.key: UIntNative)

hash(.self: &UIntNativeHashPolicy, .key: UIntNative) -> (.hash: UIntNative) := { hash = key }

eql(.self: &UIntNativeHashPolicy, .left: UIntNative, .right: UIntNative) -> (.ok: Bool) := {
    ok = [
        left
        == right
    ]
}

Int32HashPolicy: Type = ()

Int32HashPolicy implements ImplicitlyCopyable
Int32HashPolicy implements HashPolicy#(.key: Int32)

hash(.self: &Int32HashPolicy, .key: Int32) -> (.hash: UIntNative) := {
    -- Encode all signed bits numerically, including the minimum value,
    -- without depending on integer casts or native byte order.
    remaining :: Int32 = key
    hash = 0
    if remaining < 0 {
        hash = 2147483648
        remaining = remaining + 2147483647
        remaining = remaining + 1
    }
    bit :: UIntNative = 1
    while remaining > 0 {
        if remaining % 2 != 0 { hash = hash + bit }
        remaining = remaining / 2
        if remaining > 0 { bit = bit * 2 }
    }
}

eql(.self: &Int32HashPolicy, .left: Int32, .right: Int32) -> (.ok: Bool) := { ok = left == right }

StringViewHashPolicy: Type = ()

StringViewHashPolicy implements ImplicitlyCopyable
StringViewHashPolicy implements HashPolicy#(.key: StringView)

hash(.self: &StringViewHashPolicy, .key: StringView) -> (.hash: UIntNative) := {
    hash = string_hash_map_hash(.key = &key).hash
}

eql(.self: &StringViewHashPolicy, .left: StringView, .right: StringView) -> (.ok: Bool) := {
    ok = equals(.left = left, .right = right).ok
}
