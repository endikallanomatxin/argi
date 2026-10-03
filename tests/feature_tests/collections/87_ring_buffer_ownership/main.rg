Tracked : Type = (.id: Int32)
drops :: Int32 = 0
Tracked deinit(.self: $&Tracked) -> () := { drops = drops + 1 }
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= system.page_allocator
    ring ::= unwrap_or_abort(.value = RingBuffer#(.t: Tracked)(.capacity = 2, .allocator = allocator))
    a ::= Tracked(.id = 1)
    b ::= Tracked(.id = 2)
    rejected ::= Tracked(.id = 3)
    unwrap_or_abort(.value = push(.self = $&ring, .value = ~a, .allocator = allocator))
    unwrap_or_abort(.value = push(.self = $&ring, .value = ~b, .allocator = allocator))
    if is(.value = push(.self = $&ring, .value = ~rejected, .allocator = allocator), .variant = ..error) == false { abort }
    if drops != 1 { abort }
    extracted ::= unwrap_or_abort(.value = pop(.self = $&ring))
    if extracted.id != 1 { abort }
    wrapped ::= Tracked(.id = 4)
    unwrap_or_abort(.value = push(.self = $&ring, .value = ~wrapped, .allocator = allocator))
    deinit(.self = $&ring, .allocator = allocator)
    if drops != 3 or extracted.id != 1 { abort }
    deinit(.self = $&extracted)
    if drops != 4 { abort }
    strings ::= unwrap_or_abort(.value = RingBuffer#(.t: String)(.capacity = 2, .allocator = allocator))
    first ::= unwrap_or_abort(.value = String(.allocator = allocator, .length = 1))
    second ::= unwrap_or_abort(.value = String(.allocator = allocator, .length = 1))
    bytes_set(.string = $&first, .index = 0, .value = 97)
    bytes_set(.string = $&second, .index = 0, .value = 98)
    unwrap_or_abort(.value = push(.self = $&strings, .value = ~first, .allocator = allocator))
    unwrap_or_abort(.value = push(.self = $&strings, .value = ~second, .allocator = allocator))
    survivor ::= unwrap_or_abort(.value = pop(.self = $&strings))
    deinit(.self = $&strings, .allocator = allocator)
    if as_view(.self = &survivor).view != "a" { abort }
    deinit(.self = $&survivor, .allocator = allocator)
}
