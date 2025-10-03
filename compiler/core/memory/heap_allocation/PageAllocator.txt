PageAllocator : Type = struct [
    ._page_size : Int = os.page_size()
]

alloc(pa: $&PageAllocator, size: Int, alignment: Alignment) := &Byte!HeapAllocationError {
    let aligned_size = align_forward(size, max(pa.page_size, alignment.bytes))
    return os.mmap(aligned_size)
}

resize(pa: $&PageAllocator, ptr: &Byte, new_size: Int) := Bool {
    return false  // no soportado
}

dealloc(pa: $&PageAllocator, ptr: &Byte) := !HeapDeallocationError {
    os.munmap(ptr)
}

Allocator canbe PageAllocator
Allocator defaultsto PageAllocator

