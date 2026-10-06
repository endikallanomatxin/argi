..missing

attempt(.value: &Int32) -> (.result: Errable#(.t: &Int32, .reasons: (..missing))) := {
    result = ..error(.reason = ..missing)
}

main() -> () := {
    source :: Int32 = 7
    pointer ::= attempt(.value = &source) handle error, value {
        local :: Int32 = 9
        value = &local
    }
    observed ::= pointer&
}
