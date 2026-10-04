Owned: Type = (.value: Int32)

Owned deinit(.self: $&Owned) -> () := {}

accept_owned#(.t: Type: ImplicitlyCopyable)(.value: &t, .flag: Bool = true) -> (.ok: Bool) := {
    ok = flag
}

main() -> (.status_code: Int32 = 0) := {
    value :: Owned = (.value = 7)
    accept_owned(.value = &value, .flag = 3)
}
