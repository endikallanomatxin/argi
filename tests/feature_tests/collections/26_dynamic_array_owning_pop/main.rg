Tracked := (
    .id         : Int32
    .allocation : Allocation
)

drops :: Int32 = 0

implement Deinit#(Tracked) (
    .deinit = (.self: $&Tracked) -> () {
        drops = drops + 1
        deinit(.self = $&self&.allocation)
    }
)

make_tracked := #(.AllocatorType: Type: Allocator#(AllocatorType)) (
    .allocator: $&AllocatorType, .id: Int32, .error_tracer: $&Virtual#(ErrorTracer)
) -> (.result: Errable#(.t: Tracked, .reasons: (..out_of_memory))) {
    assume error_tracer

    assume allocator

    allocated ::= allocate_bytes(.self = allocator, .size = 1)
    match allocated {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok ~payload {
            value ::= Tracked(.id = id, .allocation = ~payload)
            result = ..ok ~value
        }
    }
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    array ::= unwrap_or_abort(.value = DynamicArray#(.t: Tracked)(.capacity = 1))
    made ::= make_tracked(.allocator = $&allocator_storage, .id = 7)
    match made {
        ..error _ {
            deinit(.self = $&array)
            status_code = 1
        }
        ..ok ~payload {
            item ::= ~payload
            push_assume_capacity#(.t: Tracked)(.self = $&array, .value = ~item)
            popped_result ::= pop(.self = $&array).result
            if is(.value = popped_result, .variant = ..error) {
                status_code = 2
                return
            }
            popped ::= ~popped_result ..ok

            if popped.id != 7 or length(.self = &array).count != 0 or drops != 0 {
                status_code = 2
                return
            }

            deinit(.self = $&array)
            if drops != 0 {
                status_code = 3
                return
            }

            deinit(.self = $&popped)
            if drops != 1 {
                status_code = 4
                return
            }
        }
    }
}
