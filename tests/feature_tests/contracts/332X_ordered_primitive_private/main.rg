probe#(.T: Type)(.left: T, .right: T) -> (.ok: Bool) := {
    ok = __scalar_less_than(.left = left, .right = right)
}

main := () -> () { probe(1, 2) }
