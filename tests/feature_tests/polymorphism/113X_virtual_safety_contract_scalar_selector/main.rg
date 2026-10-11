Source: Abstract = (
    get(.self: &Self) -> (.count: Int32, .result: ?Int32) where {
        on count ..some {}
    }
)

Cell: Type = ()

Cell implements Source

get(.self: &Cell) -> (.count: Int32, .result: ?Int32) := {
    count = 0
    result = ..none
}

main() -> () := {}
