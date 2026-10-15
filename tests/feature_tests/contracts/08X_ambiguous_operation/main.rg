Readable#(.Value: Type): Contract = (
    .read: (.source: &Value) -> (.value: Int32)
)
Cell: Type = (.value: Int32)
_first_read := (.source: &Cell) -> (.value: Int32) { value = source&.value }
_second_read := (.source: &Cell) -> (.value: Int32) { value = 2 }
implement Readable#(Cell) (.read = _first_read)
implement Readable#(Cell) (.read = _second_read)
-- Identical participant patterns cannot establish two conformances.
main := () -> () {}
