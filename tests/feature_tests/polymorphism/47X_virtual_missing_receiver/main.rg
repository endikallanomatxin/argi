A#(.Participant: Type): Contract = (.read: (.value: Int32) -> (.result: Int32) where {})

Box: Type = (.value: Int32)

implement A#(Box) (.read = _read)
_read(.value: Int32) -> (.result: Int32) := { result = value }

main() -> (.status_code: Int32 = 0) := {
    box :: Box = (.value = 7)
    handle ::= to_virtual#(.contract: A)(.value = $&box)
}
