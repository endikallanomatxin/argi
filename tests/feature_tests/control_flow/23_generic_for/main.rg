sum#(.t: Type: Iterable#(.t: Int32))(.input: &t) -> (.total: Int32 = 0) := {
    for item in input { total = total + item }
}

borrow_sum#(.t: Type: ROPointerIterable#(.t: Int32))(.input: &t) -> (.total: Int32 = 0) := {
    for &item in input&{ total = total + item&}
}

mutate#(.t: Type: RWPointerIterable#(.t: Int32))(.input: $&t) -> () := {
    for $&item in input&{ item&= item&+ 1 }
}

drops :: Int32 = 0

Tracked: Type = (.id: Int32)

Tracked deinit(.self: $&Tracked) -> () := { drops = drops + 1 }

consume#(.t: Type)(.input: DynamicArray#(.t: t), .allocator: $&PageAllocator) -> () := {
    assume allocator
    for ~item in input { break }
}

main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    values ::= DynamicArray#(.t: Int32)(.allocator = allocator, .capacity = 3)!
    push(.self = $&values, .value = 1, .allocator = allocator)!
    push(.self = $&values, .value = 2, .allocator = allocator)!
    push(.self = $&values, .value = 3, .allocator = allocator)!
    if sum(.input = &values).total != 6 { abort }
    if borrow_sum(.input = &values).total != 6 { abort }
    mutate(.input = $&values)
    if sum(.input = &values).total != 9 { abort }
    owners ::= DynamicArray#(.t: Tracked)(.allocator = allocator, .capacity = 2)!
    push(.self = $&owners, .value = Tracked(.id = 1), .allocator = allocator)!
    push(.self = $&owners, .value = Tracked(.id = 2), .allocator = allocator)!
    consume(.input = ~owners, .allocator = allocator)
    if drops != 2 { abort }
}
