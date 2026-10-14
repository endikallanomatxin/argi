load#(.AllocatorType: Type: Allocator#(AllocatorType))(.allocator: $&AllocatorType) -> (.status_code: Int32) := {
    assume allocator

    status_code = 45
}
