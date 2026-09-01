InfalliblyCopyable : Abstract = (
    copy(.self: &Self) -> (.value: Self)
)

FalliblyCopyable#(.reasons: Type) : Abstract = (
    copy(.self: &Self) -> (.result: Errable#(.t: Self, .reasons: reasons))
)

ImplicitlyCopyable : Abstract = ()
ImplicitlyCopyable implements InfalliblyCopyable

Int8 implements ImplicitlyCopyable
Int16 implements ImplicitlyCopyable
Int32 implements ImplicitlyCopyable
Int64 implements ImplicitlyCopyable
UIntNative implements ImplicitlyCopyable
UInt8 implements ImplicitlyCopyable
UInt16 implements ImplicitlyCopyable
UInt32 implements ImplicitlyCopyable
UInt64 implements ImplicitlyCopyable
Float16 implements ImplicitlyCopyable
Float32 implements ImplicitlyCopyable
Float64 implements ImplicitlyCopyable
Char implements ImplicitlyCopyable
Bool implements ImplicitlyCopyable
Void implements ImplicitlyCopyable

copy#(.t: Type: ImplicitlyCopyable)(.self: &t) -> (.value: t) := {
    value = self&
}
