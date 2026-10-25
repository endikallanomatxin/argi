first_drops :: Int32 = 0
second_drops :: Int32 = 0

Resource: Type = (.id: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        if self&.id == 1 {
            first_drops = first_drops + 1
        } else {
            second_drops = [second_drops + 1]
        }
    }
)

EmptyResource: Type = ()

empty_drops :: Int32 = 0

implement Deinit#(EmptyResource) (
    .deinit = (.self: $&EmptyResource) -> () {
        empty_drops = empty_drops + 1
    }
)

Box: Type = (.resource: $&Resource)

main() -> (.status_code: Int32) := {
    {
        values :: [2]Resource = (Resource(.id = 1), Resource(.id = 2))
        second ::= trusted_mutable_reference_offset(
            .base = $&values[0], .elements = 1
        ).reference
        deinit(.self = second)
        if first_drops != 0 or second_drops != 1 { abort }
    }
    if first_drops != 1 or second_drops != 1 { abort }
    {
        empty :: [2]EmptyResource = (EmptyResource(), EmptyResource())
        second ::= trusted_mutable_reference_offset(.base = $&empty[0], .elements = 1).reference
        deinit(.self = second)
        if empty_drops != 1 { abort }
    }
    if empty_drops != 2 { abort }
    {
        resource :: Resource = Resource(.id = 2)
        box :: Box = (.resource = $&resource)
        readonly ::= read_reference(.base = $&box).reference
        deinit(.self = readonly&.resource)
    }
    if first_drops != 1 or second_drops != 2 { abort }
    {
        first :: Resource = Resource(.id = 1)
        second :: Resource = Resource(.id = 2)
        boxes :: [2]Box = ((.resource = $&first), (.resource = $&second))
        selected ::= trusted_reference_offset(.base = &boxes[0], .elements = 1).reference
        deinit(.self = selected&.resource)
    }
    if first_drops != 2 or second_drops != 3 { abort }
    status_code = 42
}
