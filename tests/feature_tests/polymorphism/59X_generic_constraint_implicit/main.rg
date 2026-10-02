Owned : Type = (.value: Int32)
deinit(.self: $&Owned) -> () := {}

accept#(.t: Type: ImplicitlyCopyable)(.value: &t, .flag: Bool = true) -> (.ok: Bool) := { ok = flag }
main() -> (.status_code: Int32 = 0) := {
    value :: Owned = (.value = 7)
    accept(.value = &value)
}
