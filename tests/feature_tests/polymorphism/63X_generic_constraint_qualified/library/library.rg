Owned : Type = (.value: Int32)
deinit(.self: $&Owned) -> () := {}

accept#(.t: Type: ImplicitlyCopyable)(.value: &t, .flag: Bool = true) -> (.ok: Bool) := { ok = flag }
