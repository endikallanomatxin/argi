Readable#(.Value: Type): Contract = (
    .read: (.source: &Value) -> (.value: Int32)
)
Cell: Type = (.value: Int32)
implement Readable#(Cell) ()
main := () -> () {}
