Readable#(.Participant: Type): Contract = (
    .item: Type
    .read#(.other: Type)(.self: &Participant, .value: other) -> (.result: item) where {}
)
Box: Type = (.value: Int32)
implement Readable#(Box) (.item: Type = Int32, .read = _read)
_read#(.other: Type)(.self: &Box, .value: other) -> (.result: Int32) := { result = self&.value }
main() -> () := {
    box :: Box = (.value = 7)
    handle ::= to_virtual#(.contract: Readable#(.item: Int32))(.value = &box)
}
