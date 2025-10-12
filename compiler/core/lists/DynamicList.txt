DynamicList<t> : Abstract = [
    append(_, _.type)
    insert(_, _.type, Index)
    remove(_, Index)
]

List<t> canbe DynamicList<t>

DynamicList<t> canbe CopyingDynamicArray<t>
DynamicList<t> canbe SegmentedDynamicArray<t>
DynamicList<t> canbe SinglyLinkedList<t>
DynamicList<t> canbe DoublyLinkedList<t>

CopyingDynamicArray<t> : Type = [
    ---
    A heap allocated dynamic array
    that copies data when length exceeds capacity
    Fast accessing
    ---
    ._data      : &HeapAllocation
    ._data_type : Type        = t
    ._alignment : Alignment   = ..Default
    ._length    : Int64
    ._capacity  : Int64
]

SegmentedDynamicArray<t> : Type = [
    ---
    A heap allocated dynamic array
    that grows by getting more segments of memory, without copying data.
    Slower access than CopyingDynamicArray
    ---
    ._allocator : Allocator
    ._data      : &HeapAllocation
    ._data_type : Type        = t
    ._alignment : Alignment   = ..Default
    ._length    : Int64
    ._capacity  : Int64
]

SinglyLinkedList<t> : Type = [
	---
	---
]

DoublyLinkedList<t> : Type = [
	---
	---
]

Rope<t> : Type = [
	---
	Linked list of StaticArray
	O un Btree, no se. Decidir como implementamos esto.
	---
]

