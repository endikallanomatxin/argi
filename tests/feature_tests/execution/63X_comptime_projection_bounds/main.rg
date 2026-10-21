values() -> (.data: [2]Int32 = (20, 42)) := {}

index() -> (.result: UIntNative = 2) := {}

identity(.value: Int32) -> (.result: Int32 = value) := {}

main() -> (.status_code: Int32 = 0) := {
    status_code = #run () -> (.value: Int32) { value = identity(.value = values()[index()]) }
}
