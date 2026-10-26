Capability<.Participant: Type>: Contract = (
    .item : Type
)

Group<.Left: Type, .Right: Type>: Contract = (
    .Result : Type: Capability<.item: Left>
)

Row: Type = ()

Column: Type = ()

implement Capability<Row> (.item: Type = Row)

implement Group<Row, Column> (.Result: Type = Row)

main := () -> () {}
