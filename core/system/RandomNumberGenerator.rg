-- System entropy is separate from deterministic Pcg32 state.
-- TODO: Add operating-system entropy through this capability.
RandomNumberGenerator : Type = ()

once RandomNumberGenerator init() -> (.result: RandomNumberGenerator) := {
    result = ()
}
