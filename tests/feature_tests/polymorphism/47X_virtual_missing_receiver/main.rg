A : Abstract = (read(.value: Int32) -> (.result: Int32))
Box : Type = (.value: Int32)
Box implements A
read(.value: Int32) -> (.result: Int32) := { result = value }
main() -> (.status_code: Int32 = 0) := {
    box :: Box = (.value = 7)
    handle ::= to_virtual#(.abstract: A)(.value = $&box)
}
