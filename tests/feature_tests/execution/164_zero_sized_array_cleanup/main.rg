Zero: Type = ()

drops :: Int32 = 0

implement Deinit#(Zero) (
    .deinit = (.self: $&Zero) -> () { drops = drops + 1 }
)

main := () -> (.status_code: Int32) {
    {
        values :: [2]Zero = (
            (),
            ()
        )
        deinit(.self = $&values[0])
    }
    if drops != 2 { abort }
    {
        values :: [2]Zero = (
            (),
            ()
        )
        moved ::= ~values[0]
    }
    if drops != 4 { abort }
    status_code = 42
}
