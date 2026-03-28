Counter : Type = (
    .count: UIntNative
)

length(.self: &Counter) -> (.count: UIntNative) := {
    count = self&.count
}

main() -> (.status_code: Int32) := {
    counter :: Counter = (
        .count = 7
    )

    if length(.self = &counter).count != 7 {
        status_code = 1
        return
    }

    if length(.value = (1, 2, 3)) != 3 {
        status_code = 2
        return
    }

    status_code = 0
}
