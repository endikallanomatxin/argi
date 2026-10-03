Owned : Type = (.value: Int32)
Owned deinit(.self: $&Owned) -> () := {}

accept#(.t: Type: ImplicitlyCopyable)(.value: &t, .flag: Bool = true) -> (.ok: Bool) := { ok = flag }
