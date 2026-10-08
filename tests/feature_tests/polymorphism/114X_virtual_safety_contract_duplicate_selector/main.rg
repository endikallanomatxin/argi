Source: Abstract = (
    get(.self: &Self) -> (.first: ?Int32, .second: ?Int32) where {
        on first ..some {}
        on second ..some {}
        on second ..some {}
    }
)

Cell: Type = ()

Cell implements Source

get(.self: &Cell) -> (.first: ?Int32, .second: ?Int32) := {
    first = ..none
    second = ..none
}

main() -> () := {}
