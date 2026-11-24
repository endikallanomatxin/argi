-- The nominal owner vouches that every valid value can be owned and cleaned
-- up in another execution. Lifetime and outstanding access checks still apply.
Transferable#(.T: Type): Contract = ()

-- The nominal owner vouches that moving and cleaning up this value needs
-- only the guarantees carried by its current fields or active payload.
StructurallyTransferable#(.T: Type): Contract = ()
