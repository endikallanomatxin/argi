First : Type = (..ok Int32, ..error Int32)
Second : Type = (..ok Int32, ..error StringView)
FirstWrapper : Type = (.value: First)
SecondWrapper : Type = (.value: Second)
main() -> (.status_code: Int32 = 0) := {
    first ::= FirstWrapper(.value = ..ok 42)
    second ::= SecondWrapper(.value = ..ok 7)
    if first.value..ok != 42 { abort }
    if second.value..ok != 7 { abort }
}
