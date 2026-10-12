InfalliblyCopyable: Contract = (
    copy(.self: &Self) -> (.value: Self)
)

FalliblyCopyable: Contract = (
    .reasons: Type

    copy(.self: &Self, .allocator: $&Allocator) -> (.result: Errable#(Self, reasons))
)

ImplicitlyCopyable: Contract = ()

ImplicitlyCopyable satisfies InfalliblyCopyable

Int8 satisfies ImplicitlyCopyable
Int16 satisfies ImplicitlyCopyable
Int32 satisfies ImplicitlyCopyable
Int64 satisfies ImplicitlyCopyable
UIntNative satisfies ImplicitlyCopyable
UInt8 satisfies ImplicitlyCopyable
UInt16 satisfies ImplicitlyCopyable
UInt32 satisfies ImplicitlyCopyable
UInt64 satisfies ImplicitlyCopyable
Float16 satisfies ImplicitlyCopyable
Float32 satisfies ImplicitlyCopyable
Float64 satisfies ImplicitlyCopyable
Char satisfies ImplicitlyCopyable
Bool satisfies ImplicitlyCopyable
Void satisfies ImplicitlyCopyable

copy#(.t: Type: ImplicitlyCopyable)(.self: &t) -> (.value: t) := {
    value = self&
}
