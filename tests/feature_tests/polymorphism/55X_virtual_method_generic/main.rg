Readable#(.item: Type): Abstract = (
    read#(.other: Type)(.self: &Self, .value: other) -> (.result: item)
)
Box: Type = (.value: Int32)
Box implements Readable#(.item: Int32)
read#(.other: Type)(.self: &Box, .value: other) -> (.result: Int32) := { result = self&.value }
main() -> () := {
    box :: Box = (.value = 7)
    handle ::= to_virtual#(.abstract: Readable#(.item: Int32))(.value = &box)
}
