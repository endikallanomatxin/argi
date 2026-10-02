less#(.t: Type)(.left: t, .right: t) -> (.ok: Bool) := { ok = left < right }
main() -> () := {
    observed ::= less#(.t: StringView)(.left = "a", .right = "b").ok
}
