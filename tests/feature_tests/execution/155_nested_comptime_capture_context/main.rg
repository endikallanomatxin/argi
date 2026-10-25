compute() -> (.value: Int32 = 40) := {}

main() -> (.status_code: Int32) := {
    known := compute()
    captured := #run () -> (.answer: Int32) {
        first := #run () -> (.answer: Int32) { answer = known + 1 }
        second := #run () -> (.answer: Int32) { answer = first + 1 }
        #if true { answer = second } #else { answer = missing() }
    }
    repeated := #run () -> (.answer: Int32) {
        index :: Int32 = 0
        total :: Int32 = 0
        while index < 2 {
            total = total + [#run () -> (.value: Int32) { value = index + 20 }]
            index = index + 1
        }
        answer = total + 1
    }
    if captured != 42 or repeated != 42 { abort }
    status_code = captured
}
