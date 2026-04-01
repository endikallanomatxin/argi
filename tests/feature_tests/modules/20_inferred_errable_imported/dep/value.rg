..import_error

fail() -> (.result: Errable#(.t: Int32, .reasons: (..import_error))) := {
    result = ..error(.reason = ..import_error)
}

load() -> !Int32 := {
    value := fail()!
    result = ..ok(.value = value)
}
