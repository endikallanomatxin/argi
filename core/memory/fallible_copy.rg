FalliblyCopyable#(.Value: Type): Contract = (
    .reasons : Type
    .copy    : (.self: &Value, .allocator: Virtual#(Allocator)) -> (.result: Errable#(Value, reasons))
)

implement#(.Value: Type: InfalliblyCopyable) FalliblyCopyable#(Value) (
    .reasons : Type = (..out_of_memory)
    .copy    = (.self: &Value, .allocator: Virtual#(Allocator)) -> (.result: Errable#(Value, reasons)) {

        result = ..ok InfalliblyCopyable#(Value).copy(.self = self)
    }
)
