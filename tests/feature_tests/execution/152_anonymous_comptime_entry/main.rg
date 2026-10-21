calculate(.value: Int32) -> (.result: Int32) := { result = value + 1 }

enabled() -> (.result: Bool) := { result = true }

module_answer ::= #run () -> (.result: Int32 = 42) {}

Record: Type = (.value: Int32 = #run () -> (.result: Int32 = 42) {})

main() -> (.status_code: Int32) := {
    record ::= Record()
    if record.value != module_answer { abort }
    #run {
        local :: Int32 = 41
        pointer ::= $&local
        pointer&= pointer&+ 1
        if local != 42 { abort }
    }
    first ::= #run () -> (.result: Int32 = 20) {}
    pair ::= #run () -> (.left: Int32, .right: Int32) {
        left = 20
        right = 22
    }
    if pair.left + pair.right != 42 { abort }
    selected ::= #run () -> (.result: Int32) {
        #if enabled() {
            local ::= 42
            result = local
        } #else {
            result = missing()
        }
    }
    if selected != 42 { abort }
    second ::= #run () -> (.result: Int32) {
        local ::= #run () -> (.result: Int32 = 21) {}
        pointer ::= &local
        result = calculate(.value = pointer&)
    }
    status_code = first + second
}
