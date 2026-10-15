Source#(.Participant: Type): Contract = (
    .get: (.self: &Participant) -> (.result: ?Int32) where {
        on missing ..some {}
    }
)

main() -> () := {}
