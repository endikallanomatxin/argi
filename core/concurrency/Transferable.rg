-- The nominal owner vouches that every valid value can be owned and cleaned
-- up in another execution. Lifetime and outstanding access checks still apply.
Transferable#(.T: Type): Contract = ()
