-- A strict weak order: irreflexive and transitive, with transitive equivalence
-- when neither direction is less. Results remain stable during an algorithm.
OrderPolicy#(.Policy: Type, .t: Type: ImplicitlyCopyable): Contract = (
    .less : (.self: &Policy, .left: t, .right: t) -> (.ok: Bool)
)

Int32OrderPolicy: Type = ()

Int32OrderPolicy satisfies ImplicitlyCopyable

implement OrderPolicy#(Int32OrderPolicy, Int32)(
    .less = (.self: &Int32OrderPolicy, .left: Int32, .right: Int32) -> (.ok: Bool) {
        ok = [
            left
            < right
        ]
    }
)

UIntNativeOrderPolicy: Type = ()

UIntNativeOrderPolicy satisfies ImplicitlyCopyable

implement OrderPolicy#(UIntNativeOrderPolicy, UIntNative)(
    .less = (.self: &UIntNativeOrderPolicy, .left: UIntNative, .right: UIntNative) -> (.ok: Bool) {
        ok = [
            left
            < right
        ]
    }
)

StringViewOrderPolicy: Type = ()

StringViewOrderPolicy satisfies ImplicitlyCopyable

implement OrderPolicy#(StringViewOrderPolicy, StringView)(
    .less = (.self: &StringViewOrderPolicy, .left: StringView, .right: StringView) -> (.ok: Bool) {
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
)
