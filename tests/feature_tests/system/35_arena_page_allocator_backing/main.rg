main() -> (.status_code: Int32) := {
    pages :: PageAllocator = PageAllocator()
    arena :: ArenaAllocator = ArenaAllocator(.backing_allocator = $&pages, .block_size = 4096)
    allocator :: Virtual#(.abstract: Allocator) = to_virtual#(.abstract: Allocator)(.value = $&arena)
    data ::= allocate(.self = $&allocator, .size = 1)
    data& = 7
    if data& == 7 {
        status_code = 0
    } else {
        status_code = 1
    }
    deinit(.self = $&arena)
}
