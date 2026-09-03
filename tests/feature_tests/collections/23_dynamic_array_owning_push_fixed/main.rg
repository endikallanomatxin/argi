Tracked : Type = (
    .id: Int32
    .allocation: Allocation
)

first_drops :: Int32 = 0
second_drops :: Int32 = 0
third_drops :: Int32 = 0

deinit(.self: $&Tracked) -> () := {
    if self&.id == 1 { first_drops = first_drops + 1 }
    if self&.id == 2 { second_drops = second_drops + 1 }
    if self&.id == 3 { third_drops = third_drops + 1 }
    deinit(.self = $&self&.allocation)
}

make_tracked(.allocator: $&Allocator, .id: Int32) -> (.result: Errable#(.t: Tracked, .reasons: (..out_of_memory))) := {
    allocation_result ::= allocate(.self = allocator, .size = 1)
    match allocation_result {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok ~ payload {
            value ::= Tracked(.id = id, .allocation = ~payload)
            result = ..ok ~value
        }
    }
}

BackingAllocator : Type = ()
backing_deallocations :: Int32 = 0
backing_freed_after_elements :: Bool = false

init(.p: $&BackingAllocator) -> () := {}

allocate(.self: $&BackingAllocator, .size: UIntNative) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    storage ::= malloc(.size = size)
    address :: UIntNative = cast#(.to: UIntNative)(.value = storage)
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
    allocation ::= establish_allocation(.storage = storage, .size = size, .deallocator = deallocator)
    result = ..ok ~allocation
}

deallocate(.self: $&BackingAllocator, .data: $&UInt8, .size: UIntNative) -> () := {
    backing_freed_after_elements = first_drops == 1 and second_drops == 1 and third_drops == 1
    backing_deallocations = backing_deallocations + 1
    address :: UIntNative = cast#(.to: UIntNative)(.value = data)
    free(.address = address)
}

BackingAllocator implements Allocator
BackingAllocator implements Deallocator

main(.system: System) -> (.status_code: Int32) := {
    backing :: BackingAllocator = BackingAllocator()
    array ::= DynamicArray#(.t: Tracked)(.allocator = $&backing, .capacity = 3)
    #keep array

    first_result ::= make_tracked(.allocator = system.allocator, .id = 1)
    match first_result {
        ..error _ { status_code = 10 }
        ..ok ~ first_payload {
            first ::= ~first_payload
            second_result ::= make_tracked(.allocator = system.allocator, .id = 2)
            match second_result {
                ..error _ { status_code = 11 }
                ..ok ~ second_payload {
                    second ::= ~second_payload
                    third_result ::= make_tracked(.allocator = system.allocator, .id = 3)
                    match third_result {
                        ..error _ { status_code = 12 }
                        ..ok ~ third_payload {
                            third ::= ~third_payload
                            push#(.t: Tracked)(.allocator = $&backing, .self = $&array, .value = ~first)
                            push#(.t: Tracked)(.allocator = $&backing, .self = $&array, .value = ~second)
                            push#(.t: Tracked)(.allocator = $&backing, .self = $&array, .value = ~third)

                            if first_drops != 0 or second_drops != 0 or third_drops != 0 {
                                status_code = 20
                                return
                            }

                            deinit#(.t: Tracked)(.allocator = $&backing, .self = $&array)
                            if first_drops != 1 or second_drops != 1 or third_drops != 1 {
                                status_code = 21
                                return
                            }
                            if backing_deallocations != 1 or backing_freed_after_elements == false {
                                status_code = 22
                                return
                            }
                            status_code = 0
                        }
                    }
                }
            }
        }
    }
}
