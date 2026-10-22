FailingAllocator: Type = ()

ProbeTracer: Type = (.count: UIntNative = 0)

implement Allocator#(FailingAllocator) (
    .allocate = (.self: $&FailingAllocator, .size: UIntNative, .alignment: UIntNative) -> (
        .result : Errable#(Allocation, (..out_of_memory))
    ) { result = ..error(.reason = ..out_of_memory) }
)

implement ErrorTracer#(ProbeTracer) (
    .add_context = (.self: $&ProbeTracer, .location: SourceLocationId, .context: StringView) -> (
    ) {
        self&.count = self&.count + 1
    }
    .reset_context = (.self: $&ProbeTracer) -> () { self&.count = 0 }
    .report        = (.self: $&ProbeTracer, .writer: $&Virtual#(.contract: Writer)) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) { result = ..ok Void() }
)

main() -> (.status_code: Int32) := {
    tracer ::= ProbeTracer()
    handle ::= to_virtual#(.contract: ErrorTracer)(.value = $&tracer)
    assume error_tracer ::= $&handle
    allocator ::= FailingAllocator()
    allocated ::= allocate#(.t: UInt8)(.self = $&allocator, .count = 2)
    match allocated {
        ..ok ~payload { abort }
        ..error failure {
            if failure.reason != ..out_of_memory { abort }
            if tracer.count != 1 { abort }
            add_context(.context = "original allocation error", .error_tracer = failure.tracer)
            if tracer.count != 2 { abort }
        }
    }
    status_code = 42
}
