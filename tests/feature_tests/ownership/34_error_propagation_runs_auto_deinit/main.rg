Resource : Type = ()

dummy_counter :: Int32 = 0
init(.p: $&Resource) -> () := {
}

deinit(.res: $&Resource) -> () := {
    dummy_counter = dummy_counter + 1
}

fail() -> (.result: Errable#(.t: Int32, .reason: Char)) := {
    result = ..error(.reason = 'x')
}

propagate() -> (.result: Errable#(.t: Int32, .reason: Char)) := {
    handle := Resource()
    value := fail()!
    if dummy_counter != 1 {
        result = ..error(.reason = 'y')
        return
    }
    result = ..ok(.value = value)
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
