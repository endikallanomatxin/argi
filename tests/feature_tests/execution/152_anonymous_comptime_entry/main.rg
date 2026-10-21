calculate(.value: Int32) -> (.result: Int32) := { result = value + 1 }

main() -> (.status_code: Int32) := {
    #run {
        local :: Int32 = 41
        pointer ::= $&local
        pointer&= pointer&+ 1
        if local != 42 { abort }
    }
    first ::= #run () -> (.result: Int32 = 20) {}
    second ::= #run () -> (.result: Int32) {
        local ::= #run () -> (.result: Int32 = 21) {}
        pointer ::= &local
        result = calculate(.value = pointer&)
    }
    status_code = first + second
}
