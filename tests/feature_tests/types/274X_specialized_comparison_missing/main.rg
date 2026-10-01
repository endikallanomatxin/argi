Record : Type = (.value: Int32)
Record implements ImplicitlyCopyable
same#(.t: Type)(.left: t, .right: t) -> (.ok: Bool) := { ok = left == right }
main() -> () := {
    a :: Record = (.value = 1)
    b :: Record = (.value = 1)
    observed ::= same#(.t: Record)(.left = a, .right = b).ok
}
