Direction : Type = (
    ..north,
    ..east,
    ..south,
    ..west,
)

Result: Type = (
    ..ok(.value: Int32),
    ..error(.code: Int32),
)

choice_equality := () -> (.passed: Bool) {
    dir: Direction = ..south
    passed = dir == ..south and dir != ..north
}

payload_extraction := () -> (.value: Int32) {
    result: Result = ..ok(.value = 7)
    payload := result ..ok
    value = payload.value
}

payloadless_match := (.direction: Direction) -> (.value: Int32) {
    match direction {
        ..north { value = 1 }
        ..east { value = 2 }
        ..south { value = 3 }
        ..west { value = 4 }
    }
}

payload_match := (.result: Result) -> (.value: Int32) {
    match result {
        ..ok payload { value = payload.value }
        ..error err {
            if err.code == 120 { value = 10 } else { value = 11 }
        }
    }
}

main := () -> (.status_code: Int32 = 0) {
    if choice_equality() == false { status_code = 1 return }
    if payload_extraction() != 7 { status_code = 2 return }
    if payloadless_match(.direction = ..north) != 1 { status_code = 3 return }
    if payloadless_match(.direction = ..south) != 3 { status_code = 4 return }
    if payload_match(.result = ..ok(.value = 9)) != 9 { status_code = 5 return }
    if payload_match(.result = ..error(.code = 120)) != 10 { status_code = 6 return }
}
