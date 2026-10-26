Product<.Left: Type, .Right: Type>: Contract = (
    .Result : Type

    .multiply : (.left: Left, .right: Right) -> (.value: Result) where {}
)

Row: Type = ()

Column: Type = ()

_multiply := (.left: Row, .right: Column) -> (.value: Int32) { value = 42 }

implement Product<Row, Column> (.Result: Type = Int32, .multiply = _multiply)
