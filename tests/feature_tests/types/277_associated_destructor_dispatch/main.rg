drops :: Int32 = 0
record_drop(.amount: Int32) -> () := { drops = drops + amount }
Box#(.t: Type) : Type = (.value: t)
Other : Type = (.value: Int32)
Box deinit#(.t: Type)(.allocator: $&Allocator, .box: $&Box#(.t: t)) -> () := {
    record_drop(.amount = 1)
    nested ::= Other(.value = 0)
    deinit(.self = $&nested)
}
Other deinit(.self: $&Other) -> () := { record_drop(.amount = 10) }
exercise(.allocator: $&Allocator) -> () := {
    assume allocator
    first ::= Box#(.t: Int32)(.value = 4)
    second ::= Box#(.t: Char)(.value = 'a')
    other ::= Other(.value = 9)
    explicit ::= Other(.value = 3)
    deinit(.self = $&explicit)
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: Box#(.t: Char))(.capacity = 1))
    element ::= Box#(.t: Char)(.value = 'b')
    pushed ::= push#(.t: Box#(.t: Char))(.self = $&array, .value = ~element)
    if is(.value = pushed, .variant = ..error) { abort }
}
main(.system: System) -> (.status_code: Int32) := {
    exercise(.allocator = system.page_allocator)
    if drops != 53 {
        status_code = 1
        return
    }
    status_code = 0
}
