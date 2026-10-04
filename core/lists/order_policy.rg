-- A strict weak order: irreflexive and transitive, with transitive equivalence
-- when neither direction is less. Results remain stable during an algorithm.
OrderPolicy#(.t: Type: ImplicitlyCopyable): Abstract = (
    less(.self: &Self, .left: t, .right: t) -> (.ok: Bool)
)

Int32OrderPolicy: Type = ()

Int32OrderPolicy implements ImplicitlyCopyable
Int32OrderPolicy implements OrderPolicy#(.t: Int32)

less(.self: &Int32OrderPolicy, .left: Int32, .right: Int32) -> (.ok: Bool) := { ok = left < right }

UIntNativeOrderPolicy: Type = ()

UIntNativeOrderPolicy implements ImplicitlyCopyable
UIntNativeOrderPolicy implements OrderPolicy#(.t: UIntNative)

less(.self: &UIntNativeOrderPolicy, .left: UIntNative, .right: UIntNative) -> (.ok: Bool) := {
    ok = [
        left
        < right
    ]
}

StringViewOrderPolicy: Type = ()

StringViewOrderPolicy implements ImplicitlyCopyable
StringViewOrderPolicy implements OrderPolicy#(.t: StringView)

less(.self: &StringViewOrderPolicy, .left: StringView, .right: StringView) -> (.ok: Bool) := {
    index :: UIntNative = 0
    while index < left.length and index < right.length {
        left_byte ::= bytes_get(.view = &left, .index = index).byte
        right_byte ::= bytes_get(.view = &right, .index = index).byte
        if left_byte != right_byte {
            ok = left_byte < right_byte
            return
        }
        index = index + 1
    }
    ok = left.length < right.length
}
