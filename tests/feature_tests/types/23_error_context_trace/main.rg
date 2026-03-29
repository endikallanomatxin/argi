fail() -> (.result: Errable#(.t: Int32, .reason: Char)) := {
    result = ..error(.reason = 'x')
}

propagate() -> (.result: Errable#(.t: Int32, .reason: Char)) := {
    value := fail() !! "while reading foo"
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
        if entry.line != 6 {
            status_code = 2
            return
        }

        if entry.column != 21 {
            status_code = 3
            return
        }

        if entry.context& != 'w' {
            status_code = 4
            return
        }

        status_code = 0
    } else {
        status_code = 5
    }
}
