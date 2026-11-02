Box := #(.t: Type) (.value: t)

implement#(.t: Type: ImplicitlyCopyable) ImplicitlyCopyable#(Box#(.t: t)) ()

implement#(.t: Type) Equal#(Box#(.t: t), Box#(.t: t)) (
    .equal = (.left: Box#(.t: t), .right: Box#(.t: t), .bias: Int32 = 0) -> (.ok: Bool) {
        ok = left.value == right.value and bias == 7
    }
)

same := #(.t: Type) (.left: t, .right: t) -> (.ok: Bool) {
    assume bias :: Int32 = 7
    ok = left == right
}

main := () -> (.status_code: Int32 = 0) {
    a :: Box#(.t: UIntNative) = (.value = 9)
    b :: Box#(.t: UIntNative) = (.value = 9)
    if same#(.t: Box#(.t: UIntNative))(.left = a, .right = b).ok == false { abort }
}
