Source#(.Participant: Type): Contract = (
    .get: (.self: &Participant) -> (.first: ?Int32, .second: ?Int32) where {
        on first ..some {}
        on second ..some {}
        on second ..some {}
    }
)

Cell: Type = ()

implement Source#(Cell) (.get = _impl_get_Cell)

_impl_get_Cell := (.self: &Cell) -> (.first: ?Int32, .second: ?Int32)  {
    first = ..none
    second = ..none
}

main() -> () := {}
