A#(.item: Type) : Abstract = ()
Box : Type = (.value: Int32)
Box implements A#(.item: Int32)
main() -> (.status_code: Int32 = 0) := {
    box :: Box = (.value = 7)
    handle ::= to_virtual#(.abstract: A#(.item: Int32))(.value = $&box)
}
