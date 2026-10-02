Box#(.t: Type) : Type = (.value: t)
Box#(.t: Type: ImplicitlyCopyable) implements ImplicitlyCopyable
operator == #(.t: Type)(.left: Box#(.t: t), .right: Box#(.t: t), .bias: Int32 = reach bias) -> (.ok: Bool) := {
    ok = left.value == right.value and bias == 7
}
same#(.t: Type)(.left: t, .right: t) -> (.ok: Bool) := {
    assume bias :: Int32 = 7
    ok = left == right
}
main() -> (.status_code: Int32 = 0) := {
    a :: Box#(.t: UIntNative) = (.value = 9)
    b :: Box#(.t: UIntNative) = (.value = 9)
    if same#(.t: Box#(.t: UIntNative))(.left = a, .right = b).ok == false { abort }
}
