-- Removal selects the queue's result protocol without an allocation provider.
Queue#(.Collection: Type): Contract = (
    .Item   : Type
    .Result : Type
    .pop    : (.self: $&Collection) -> (.result: Result)
)

-- A bounded queue retains the provider needed to clean rejected owning inputs.
QueueInsertion#(.Collection: Type, .Provider: Type: Allocator#(Provider)): Contract = (
    Queue#(Collection)
    .Result : Type
    .push   : (.self: $&Collection, .value: Queue#(Collection).Item, .allocator: $&Provider) -> (
        .result : Result
    )
)
