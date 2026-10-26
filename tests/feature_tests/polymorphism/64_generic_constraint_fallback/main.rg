Owned := (.value: Int32)

implement Deinit<Owned> (
    .deinit = (.self: $&Owned) -> () {

    }
)

Acceptance<.Value: Type>: Contract = (
    .accept : (.value: &Value, .flag: Bool = true) -> (.ok: Bool)
)

implement Acceptance<Owned> (
    .accept = (.value: &Owned, .flag: Bool = true) -> (.ok: Bool) { ok = flag }
)

implement<.Value: Type: ImplicitlyCopyable> Acceptance<Value> (
    .accept = (.value: &Value, .flag: Bool = true) -> (.ok: Bool) { ok = flag }
)

main := () -> (.status_code: Int32 = 0) {
    value :: Owned = (.value = 7)
    if accept(.value = &value).ok == false { status_code = 1 }
}
