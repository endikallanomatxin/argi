Inner : Type = (
    .item: &Int32
)

Outer : Type = (
    .inner: Inner
)

read(.inner: Inner) -> (.value: Int32) := {
    value = inner.item&
}

main() -> (.status_code: Int32) := {
    original :: Int32 = 1
    outer :: Outer = (.inner = Inner(.item = &original))
    if true {
        temporary :: Int32 = 2
        outer.inner.item = &temporary
    }
    copied ::= outer.inner
    status_code = read(.inner = copied)
}
