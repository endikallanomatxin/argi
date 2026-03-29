..test_error

fail() -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) := {
    result = ..error(.reason = ..test_error)
}

propagate() -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) := {
    value := fail()!
    result = ..ok(.value = value)
}

main() -> (.status_code: Int32) := {
    zero :: UIntNative = 0
    one :: UIntNative = 1
    result := propagate()

    if is(.value = result, .variant = ..error) {
        err := result..error
        if err.trace.entries.length != one {
            status_code = 1
            return
        }

        entry := err.trace.entries[zero]
        if entry.line != 8 {
            status_code = 2
            return
        }

        if entry.column != 20 {
            status_code = 3
            return
        }

        status_code = 0
    } else {
        status_code = 4
    }
}
