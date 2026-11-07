-- Private receipts retain execution access until the task has joined.
_ExecutionJoin := (._handle: UIntNative, ._ffi: $&ForeignFunctionInterface)
_ExecutionReceipt := (._marker: UInt8 = 0, ._handle: UIntNative = 0)

-- This audited operation performs the join, rather than accepting a caller's
-- assertion that work finished. Its handle is installed only by acceptance.
_execution_reclaim_native(.handle: UIntNative) -> (.status: CInt): CFunction(
    .symbol = "_argi_execution_reclaim"
) where { no_access() }

implement Deinit#(_ExecutionReceipt) (
    .deinit = (.self: $&_ExecutionReceipt) -> () {
        _execution_complete(.receipt = self)
    }
)

_execution_lend := #(.t: Type) (.inputs: t) -> (.receipt: _ExecutionReceipt) {
    receipt = (._marker = 1)
}

_execution_accept := (
    .receipt: $&_ExecutionReceipt, .handle: UIntNative
) -> () {
    if receipt&._marker != 1 or handle == 0 { abort }
    receipt&._handle = handle
    receipt&._marker = 2
}

_execution_complete := (.receipt: $&_ExecutionReceipt, .join: ?_ExecutionJoin = ..none) -> () {
    if receipt&._marker > 2 or [receipt&._marker == 1 and receipt&._handle != 0] { abort }
    if receipt&._marker == 2 {
        match join {
            ..none { abort }
            ..some joined {
                if joined.value._handle != receipt&._handle { abort }
                assume ffi := joined.value._ffi
                if _execution_reclaim_native(.handle = joined.value._handle) != 0 { abort }
            }
        }
    }
    receipt&._marker = 0
}

-- A private callback argument, minted by the adapter from its acquired buffers.
-- It is not an application-constructible certificate for an arbitrary address.
_ExecutionInvocation: CStruct = (
    ._identity: UIntNative, ._input: UIntNative, ._output: UIntNative,
    ._input_size: UIntNative, ._output_size: UIntNative,
    ._input_alignment: UIntNative, ._output_alignment: UIntNative
)

_execution_input := #(.t: Type) (.invocation: _ExecutionInvocation, .anchor: &Any) -> (.reference: $&t) {
    if invocation._identity == 0 or invocation._input == 0 or
        invocation._input_size != size_of(.type = t) or
        invocation._input_alignment != alignment_of(.type = t) or
        invocation._input % alignment_of(.type = t) != 0 { abort }
    reference = trusted_establish_inherited_reference#(t)(
        .raw = raw_pointer#(t)(.address = invocation._input), .root = anchor
    )
}
