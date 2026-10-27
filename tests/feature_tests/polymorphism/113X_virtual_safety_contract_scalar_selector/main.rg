Source#(.Participant: Type): Contract = (
    .get : (.self: &Participant) -> (.count: Int32, .result: ?Int32) where {
        on count ..some {}
    }
)

Cell: Type = ()

implement Source#(Cell) (.get = _impl_get_Cell)

_impl_get_Cell := (.self: &Cell) -> (.count: Int32, .result: ?Int32) {
    count = 0
    result = ..none
}

main := () -> () {}
