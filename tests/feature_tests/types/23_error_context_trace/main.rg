..test_error

fail() -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) := {
    result = ..error(.reason = ..test_error)
}

propagate() -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) := {
    value := fail() !! "while reading foo"
    result = ..ok value
}

main() -> (.status_code: Int32) := {
    zero :: UIntNative = 0
    one :: UIntNative = 1
    result := propagate()

    if is(.value = result, .variant = ..error) {
        err ::= &result..error
        if length#(.t: ErrorTraceEntry)(.self = &err&.trace.entries).count != one {
            status_code = 1
            return
        }

        entry_result ::= get#(.t: ErrorTraceEntry)(.self = &err&.trace.entries, .index = zero).result
        if is(.value = entry_result, .variant = ..error) {
            status_code = 6
            return
        }
        entry ::= entry_result..ok
        if entry.line != 8 {
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
