main(.system: System) -> (.status_code: Int32 = 0) := {
    bytes: [1]UInt8 = (0)
    fill_random_bytes(.self = system.rand_gen, .destination = view(.array = &bytes))
}
