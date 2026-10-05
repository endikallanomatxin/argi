RecordingAllocator: Type = (
    .ffi           : $&ForeignFunctionInterface
    .allocations   : UIntNative                 = 0
    .deallocations : UIntNative                 = 0
    .fail_after    : UIntNative                 = 999
)

RecordingAllocator implements Allocator
RecordingAllocator implements Deallocator

allocate(
        .self      : $&RecordingAllocator,
        .size      : UIntNative,
        .alignment : UIntNative            = 1
    ) -> (
        .result : Errable#(Allocation, (..out_of_memory))
    ) := {
    if self&.allocations == self&.fail_after {
        result = ..error(.reason = ..out_of_memory)
        return
    }

    storage ::= malloc(.size = size, .ffi = self&.ffi)
    if UIntNative(.value = storage) == 0 {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    self&.allocations = self&.allocations + 1
    deallocator: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(
        .value = self
    )
    result = ..ok ~trusted_establish_allocation(
        .storage     = storage
        .size        = size
        .alignment   = alignment
        .deallocator = deallocator
    )
}

deallocate(
        .self      : $&RecordingAllocator,
        .data      : RawPointer#(.t: UInt8),
        .size      : UIntNative,
        .alignment : UIntNative
    ) -> () := {
    self&.deallocations = self&.deallocations + 1
    free(.address = data.address, .ffi = self&.ffi)
}

Source: Type = (.text: StringView, .position: UIntNative = 0, .fail_after: UIntNative = 999)

Source implements Reader

read_byte(.self: $&Source) -> (.result: Errable#(ReadByte, (..stream_read_failed))) := {
    if self&.position == self&.fail_after {
        result = ..error(.reason = ..stream_read_failed)
        return
    }
    if self&.position == self&.text.length {
        result = ..ok ..end
        return
    }

    byte ::= bytes_get(&self&.text, self&.position).byte
    self&.position = self&.position + 1
    result = ..ok ..ok byte
}

main(.system: System) -> !Void = ..ok Void() := {
    allocator ::= RecordingAllocator(.ffi = system.ffi)
    failed_reader ::= Source(.text = "abc", .fail_after = 1)
    match read_line(.allocator = $&allocator, .reader = $&failed_reader) {
        ..ok ~_ { abort }
        ..error error { if error.reason != ..stream_read_failed { abort } }
    }
    if allocator.allocations != 1 or allocator.deallocations != 1 { abort }

    allocator.fail_after = 2
    growing_reader ::= Source(.text = "abcdefghijklmnopq\n")
    match read_line(.allocator = $&allocator, .reader = $&growing_reader) {
        ..ok ~_ { abort }
        ..error error { if error.reason != ..out_of_memory { abort } }
    }
    if allocator.allocations != 2 or allocator.deallocations != 2 { abort }

    allocator.fail_after = 999
    eof_reader ::= Source(.text = "")
    match read_line(.allocator = $&allocator, .reader = $&eof_reader)! {
        ..end {}
        ..ok ~_ { abort }
    }
    if allocator.allocations != 3 or allocator.deallocations != 3 { abort }
}
