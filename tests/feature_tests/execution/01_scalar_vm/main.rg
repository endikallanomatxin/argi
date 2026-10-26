identity := <.T: Type> (.value: T) -> (.result: T) { result = value }

sum := (.count: Int32) -> (.result: Int32 = 0) {
    index :: Int32 = 0
    while index < count {
        index = index + 1
        if index < 3 { continue }
        if index > 8 { break }
        result = result + index
    }
}

fail := () -> (.result: Bool = false) { abort }

main := () -> (.status_code: Int32 = 0) {
    if false and fail() { abort }
    if true or fail() { status_code = identity(.value = sum(.count = 20)) + 9 }
}
