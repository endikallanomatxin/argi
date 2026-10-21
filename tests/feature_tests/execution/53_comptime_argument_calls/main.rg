identity(.value: Int32) -> (.result: Int32) := { result = value }

increment(.value: Int32) -> (.result: Int32) := { result = value + 1 }

main() -> (.status_code: Int32 = 0) := {
    computed: Int32 = increment(.value = 20 + 20)
    answer ::= #run () -> (.value: Int32) {
        value = identity(.value = increment(.value = computed))
    }
    if computed != 41 { abort }
    status_code = answer
}
