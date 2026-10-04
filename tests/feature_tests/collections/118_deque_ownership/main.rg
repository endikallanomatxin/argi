Tracked: Type = (.id: Int32)

drops :: Int32 = 0

Tracked deinit(.self: $&Tracked) -> () := { drops = drops + 1 }

main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    queue ::= Deque#(.t: Tracked)(.capacity = 2)!
    push_back(.self = $&queue, .value = Tracked(.id = 1))!
    push_back(.self = $&queue, .value = Tracked(.id = 2))!
    first ::= pop_front(.self = $&queue)!
    push_back(.self = $&queue, .value = Tracked(.id = 3))!
    push_front(.self = $&queue, .value = Tracked(.id = 4))!
    if drops != 0 { abort }
    last ::= pop_back(.self = $&queue)!
    if last.id != 3 or first.id != 1 { abort }
    deinit(.self = $&queue)
    if drops != 2 { abort }
    deinit(.self = $&first)
    deinit(.self = $&last)
    if drops != 4 { abort }
    strings ::= Deque#(.t: String)(.capacity = 1)!
    text ::= String(.allocator = allocator, .length = 1)!
    bytes_set(.string = $&text, .index = 0, .value = 65)
    push_front(.self = $&strings, .value = ~text)!
    reserve(.self = $&strings, .capacity = 8)!
    extracted ::= pop_back(.self = $&strings)!
    deinit(.self = $&strings)
    if as_view(.self = &extracted).view != "A" { abort }
}
