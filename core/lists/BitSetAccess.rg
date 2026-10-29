BitSetAccess#(.Set: Type): Contract = (
    .read_bit : (.self: &Set, .index: UIntNative, .error_tracer: $&Virtual#(ErrorTracer)) -> (
        .result : Errable#(Bool, (..out_of_bounds))
    )
    .write_bit : (
        .self: $&Set, .index: UIntNative, .value: Bool, .error_tracer: $&Virtual#(ErrorTracer)
    ) -> (.result: Errable#(Void, (..out_of_bounds)))
    .population : (.self: &Set) -> (.count: UIntNative)
)

contains_bit := #(.Set: Type: BitSetAccess#(Set)) (
    .self: &Set, .index: UIntNative, .error_tracer: $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Bool, (..out_of_bounds))) {
    assume error_tracer

    result = BitSetAccess#(Set).read_bit(.self = self, .index = index)
}

set_bit := #(.Set: Type: BitSetAccess#(Set)) (
    .self         : $&Set,
    .index        : UIntNative,
    .value        : Bool                    = true,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Void, (..out_of_bounds))) {
    assume error_tracer

    result = BitSetAccess#(Set).write_bit(.self = self, .index = index, .value = value)
}

count_set := #(.Set: Type: BitSetAccess#(Set)) (.self: &Set) -> (.count: UIntNative) {
    count = BitSetAccess#(Set).population(.self = self)
}
