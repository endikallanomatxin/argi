FalliblyCopyable#(.Value: Type, .Provider: Type: Allocator): Contract = (
    .reasons : Type
    .copy    : (.self: &Value, .allocator: $&Provider) -> (.result: Errable#(Value, reasons))
)

implement#(.Value: Type: InfalliblyCopyable, .Provider: Type: Allocator) FalliblyCopyable#(
    Value, Provider
) (
    .reasons : Type = (..out_of_memory)
    .copy    = (.self: &Value, .allocator: $&Provider) -> (.result: Errable#(Value, reasons)) {
        result = ..ok InfalliblyCopyable#(Value).copy(.self = self)
    }
)
