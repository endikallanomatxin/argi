Resource : Type = ()
..test_error
..cleanup_error

dummy_counter :: Int32 = 0
init(.p: $&Resource) -> () := {
}

deinit(.res: $&Resource) -> () := {
    dummy_counter = dummy_counter + 1
}

fail() -> (.result: Errable#(.t: Int32, .reasons: (..test_error))) := {
    result = ..error(.reason = ..test_error)
}

propagate() -> (.result: Errable#(.t: Int32, .reasons: (..test_error, ..cleanup_error))) := {
    handle := Resource()
    value := fail()!
    if dummy_counter != 1 {
        result = ..error(.reason = ..cleanup_error)
        return
    }
    result = ..ok value
}

main() -> (.status_code: Int32) := {
    dummy_counter = 0
    result := propagate()

    if is(.value = result, .variant = ..error) {
        if dummy_counter != 1 {
            status_code = 1
            return
        }
        status_code = 0
    } else {
        status_code = 2
    }
}
