Readable#(.Participant: Type): Contract = (
    .Other: Type
    .item: Type
    .Count: Int
    .read: (.other: &Other, .source: &Participant) -> (.value: &item)
        where depends_on(value, source)
)
Direct: Type = (.value: Int32)
Cell#(.item: Type): Type = (.value: item)
implement Readable#(Direct) (.Count: Int = 2, .item: Type = Int32, .Other: Type = Direct, .read = _direct_read)
implement#(.item: Type) Readable#(Cell#(item)) (.item: Type = item, .Other: Type = Cell#(item), .Count: Int = 2, .read = _cell_read)
_direct_read(.other: &Direct, .source: &Direct) -> (.value: &Int32) := { value = &source&.value }
_cell_read#(.item: Type)(.other: &Cell#(item), .source: &Cell#(item)) -> (.value: &item) := { value = &source&.value }
consume#(.item: Type, .n: Int, .T: Type: Readable#(.Other: T, .Count = n, .item: item))(
    .other: &T, .source: &T
) -> (.value: &item) := { value = read(other, source).value }
main() -> (.status_code: Int32 = 0) := {
    direct_other ::= Direct(7)
    direct ::= Direct(42)
    generic_other ::= Cell#(Int32)(8)
    generic ::= Cell#(Int32)(43)
    if consume#(.item: Int32, .n = 2, .T: Direct)(&direct_other, &direct)& != 42 { abort }
    if consume#(.item: Int32, .n = 3, .T: Cell#(Int32))(&generic_other, &generic)& != 43 { abort }
    direct_handle ::= to_virtual#(.contract: Readable#(.item: Int32, .Count = 2, .Other: Direct))(.value = &direct)
    generic_handle ::= to_virtual#(.contract: Readable#(.Other: Cell#(Int32), .item: Int32, .Count = 2))(.value = &generic)
    if read(&direct_other, &direct_handle)& != 42 { abort }
    if read(&generic_other, &generic_handle)& != 43 { abort }
}
