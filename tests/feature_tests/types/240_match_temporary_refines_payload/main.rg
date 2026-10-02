Result : Type = (
    ..ok Int32
    ..error Int32
)

make_result() -> (.result: Result) := {
    result = ..ok 42
}

main() -> (.status_code: Int32 = 1) := {
    match make_result() {
        ..ok payload { status_code = payload - 42 }
        ..error _ { status_code = 2 }
    }
}
