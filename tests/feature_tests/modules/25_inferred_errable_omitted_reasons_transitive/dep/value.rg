..import_error

fail() -> (.result: Errable#(.t: Int32, .reasons: (..import_error))) := {
    result = ..error(.reason = ..import_error)
}

load() -> (.result: Errable#(.t: Int32)) := {
    value := fail()!
    result = ..ok value
}
