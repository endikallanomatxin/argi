Inner : Type = (
    .value : Int32
)

Outer : Type = (
    .inner : Inner
)

increment(.target: $&Int32) -> () := {
    target& = target& + 1
}

read(.target: &Int32) -> (.value: Int32) := {
    value = target&
}

main() -> (.status_code: Int32) := {
    outer :: Outer = (
        .inner = (
            .value = 41
        )
    )

    increment(.target = $&outer.inner.value)

    if read(.target = &outer.inner.value).value != 42 {
        status_code = 1
        return
    }

    status_code = 0
}
