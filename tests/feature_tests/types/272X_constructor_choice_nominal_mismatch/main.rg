First : Type = (..ok Int32, ..error Int32)
Second : Type = (..ok Int32, ..error StringView)
FirstWrapper : Type = (.value: First)
main() -> () := {
    second :: Second = ..ok 7
    wrapper ::= FirstWrapper(.value = second)
}
