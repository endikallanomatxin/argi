FalliblyCopyable: Contract = (
    .reasons: Type

    copy(.self: &Self, .allocator: $&Allocator) -> (.result: Errable#(Self, reasons))
)
