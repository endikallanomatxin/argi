compute() -> (.value: Int32 = 42) := {}

main() -> (.status_code: Int32) := {
    runtime :: Int32 = 7
    known := compute()
    first := #run () -> (.answer: Int32) {
        #if true { answer = known } #else { answer = runtime }
    }
    second := #run () -> (.answer: Int32) {
        #if known == 42 { answer = known } #else { answer = missing_value }
    }
    nested := #run () -> (.answer: Int32) {
        answer = #run () -> (.value: Int32) {
            #if true { value = known } #else { value = runtime }
        }
    }
    if first != 42 or second != 42 or nested != 42 { abort }
    status_code = first
}
