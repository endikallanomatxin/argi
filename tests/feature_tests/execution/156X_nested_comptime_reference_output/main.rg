probe := #(.n: Int32) () -> (.result: Int32) {
    result = #run () -> (.answer: Int32) {
        local :: Int32 = n
        pointer: &Int32 = &local
        borrowed := #run () -> (.value: &Int32) { value = pointer }
        answer = borrowed&
    }
}

main := () -> (.status_code: Int32) { status_code = probe#(.n = 42)() }
