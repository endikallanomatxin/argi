..missing

attempt(.value: &Int32) -> (.result: Errable#(.t: &Int32, .reasons: (..missing))) := {
    result = ..error(.reason = ..missing)
}

main() -> () := {
    source :: Int32 = 7
    pointer ::= attempt(.value = &source) handle value, error {
        local :: Int32 = 9
        value = &local
    }
    observed ::= pointer&
}
