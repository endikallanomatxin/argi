-- Private receipts retain execution access until the task has joined.
_ExecutionReceipt := (._marker: UInt8 = 0)

implement Deinit#(_ExecutionReceipt) (
    .deinit = (.self: $&_ExecutionReceipt) -> () {
        if self&._marker == 2 { abort }
        _execution_complete(.receipt = self)
    }
)

_execution_lend := #(.t: Type) (.inputs: t) -> (.receipt: _ExecutionReceipt) {
    receipt = (._marker = 1)
}

_execution_accept := (.receipt: $&_ExecutionReceipt) -> () {
    receipt&._marker = 2
}

_execution_complete := (.receipt: $&_ExecutionReceipt) -> () {
    receipt&._marker = 0
}

_execution_input := #(.t: Type) (.address: UIntNative, .anchor: &Any) -> (.reference: $&t) {
    reference = trusted_establish_inherited_reference#(t)(
        .raw = raw_pointer#(t)(.address = address), .root = anchor
    )
}
