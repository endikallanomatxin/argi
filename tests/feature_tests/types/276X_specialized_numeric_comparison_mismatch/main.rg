same#(.a: Type, .b: Type)(.left: a, .right: b) -> (.ok: Bool) := { ok = left == right }
main() -> () := {
    left :: UInt64 = 1
    right :: Int64 = 1
    observed ::= same#(.a: UInt64, .b: Int64)(.left = left, .right = right).ok
}
