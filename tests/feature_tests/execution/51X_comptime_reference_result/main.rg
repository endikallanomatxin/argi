value :: Int32 = 42

reference() -> (.result: &Int32) := { result = &value }

main() -> () := {
    pointer ::= #run reference()
}
