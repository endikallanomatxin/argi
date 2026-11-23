PageSource#(.Provider: Type): Contract = (
    .backing: Region#(Provider)
    .reserve: (.self: $&Provider) -> (.result: Errable#(Allocation, (..out_of_memory))) where {
        reads(self)
        reads(self.backing)
        on result ..ok { owns(result) depends_on(result, self) }
        on result ..error {}
    }
)
implement PageSource#(PageAllocator) (
    .backing = region(self.memory)
    .reserve = (.self: $&PageAllocator) -> (.result: Errable#(Allocation, (..out_of_memory))) {
        result = Allocator#().allocate(self, .size = 1, .alignment = 1)
    }
)
main := (.system: System) -> () {
    pages ::= PageAllocator(.memory = system.memory)
    source ::= Virtual#(PageSource)($&pages)
    allocation ::= unwrap_or_abort(PageSource#().reserve(.self = $&source))
    if allocation.size != 1 { abort }
}
