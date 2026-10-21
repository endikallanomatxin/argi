value: Int32 = 42

reference() -> (.result: &Int32) := { result = &value }

main() -> () := {
    pointer ::= #run () -> (.value: &Int32) { value = reference() }
}
