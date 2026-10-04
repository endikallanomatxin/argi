main(.system: System) -> (.status_code: Int32 = 0) := {
    bytes ::= zeroed#(.t: [515]UInt8)().value
    bytes[0] = 17
    bytes[514] = 23
    whole ::= view(.array = $&bytes)
    destination ::= unwrap_or_abort(.value = slice(.self = &whole, .start = 1, .count = 513)).result
    unwrap_or_abort(.value = fill_random_bytes(.self = system.rand_gen, .destination = destination))
    if bytes[0] != 17 or bytes[514] != 23 { abort }
    empty :: [0]UInt8 = ()
    unwrap_or_abort(.value = fill_random_bytes(.self = system.rand_gen,
            .destination = view(.array = $&empty)))
    generator ::= Pcg32(.seed = 42)
    if next_uint32(.self = $&generator).value != 3270867926 { abort }
}
