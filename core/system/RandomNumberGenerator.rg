RandomNumberGenerator : Type = ()

once RandomNumberGenerator init() -> (.result: RandomNumberGenerator) := {
    result = ()

}

-- randomRIO :: Random a ⇒ (a, a) → IO a
-- Generates a random value in the given inclusive range using the global generator.
-- getStdRandom :: (StdGen → (a, StdGen)) → IO a
-- Allows purely functional use of generator operations by updating the internal seed.
-- newStdGen :: IO StdGen
-- Splits the global generator in two: one new generator for the thread, and one returned for pure use.
