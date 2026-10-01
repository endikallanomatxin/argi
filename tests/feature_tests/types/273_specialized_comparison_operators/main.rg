Box#(.t: Type) : Type = (.value: t)
Box#(.t: Type: ImplicitlyCopyable) implements ImplicitlyCopyable
operator == #(.t: Type)(.left: Box#(.t: t), .right: Box#(.t: t)) -> (.ok: Bool) := {
    ok = left.value == right.value
}
operator != #(.t: Type)(.left: Box#(.t: t), .right: Box#(.t: t)) -> (.ok: Bool) := {
    ok = left.value != right.value
}
same#(.t: Type)(.left: t, .right: t) -> (.ok: Bool) := { ok = left == right }
different#(.t: Type)(.left: t, .right: t) -> (.ok: Bool) := { ok = left != right }
below_three#(.t: Type)(.value: t) -> (.ok: Bool) := { ok = value < 3 }
main() -> (.status_code: Int32 = 0) := {
    bytes : [3]UInt8 = (97, 98, 99)
    independent :: StringView = (.data = &bytes[0], .length = 3)
    if same#(.t: StringView)(.left = independent, .right = "abc").ok == false { abort }
    if different#(.t: StringView)(.left = independent, .right = "abc").ok { abort }
    if different#(.t: StringView)(.left = independent, .right = "abd").ok == false { abort }
    a :: Box#(.t: UIntNative) = (.value = 9)
    b :: Box#(.t: UIntNative) = (.value = 9)
    c :: Box#(.t: UIntNative) = (.value = 10)
    if same#(.t: Box#(.t: UIntNative))(.left = a, .right = b).ok == false { abort }
    if different#(.t: Box#(.t: UIntNative))(.left = a, .right = b).ok { abort }
    if different#(.t: Box#(.t: UIntNative))(.left = a, .right = c).ok == false { abort }
    value :: UIntNative = 2
    if below_three#(.t: UIntNative)(.value = value).ok == false { abort }
    large :: UIntNative = 4
    if below_three#(.t: UIntNative)(.value = large).ok { abort }
}
