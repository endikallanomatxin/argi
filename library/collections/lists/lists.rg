---
GENERAL TYPES
---

Index : Type = Int64  -- 1 based index

ListAlignment : Type = [
    ..smallest_power_of_two
    ..compact
    ..custom(n: Int)
]

builtin StackBitArray<N> : Type
---
This holds a contiguous memory in the stack that is N bits long.
It directly maps to what results from alloca in LLVM.
It allows for get[] and set[] but
does not implement any of the list abstrations.
In general, don't use it. Use a StaticArray<Bit, n> instead
---


---
GENERAL LIST ABSTRACTION
---

List<t> : Abstract = [
    ---
    A list is any collection that can be indexable.
    ---
    .type : Type

    operator get[]
    operator set[]
    length() : Int
    ...
]

List<t> canbe StaticList<t, _>
List<t> canbe DynamicList<t>


---
STATIC LISTS
---

StaticList<t: Type, n: Int> : abstract = []

StaticList<t, n> canbe StackArray<t, n>
StaticList<t, n> canbe StaticArray<t, n>

StackArray<t, n> : Type = [
    ---
    This is a stack allocated array.
    Similar to the default array in C or zig, when not using malloc.
    In this language, declaration of a StackArray has to be intentional.
    ---
    ._data      : StackBitArray<n>
    ._data_type : t
    ._alignment : Alignment = ..Default
]

StaticArray<t, n> : Type = [
    ---
    A heap allocated static array
    ---
    ._data      : HeapAllocation
    ._data_type : Type        = t
    ._length    : Int         = n
    ._alignment : Alignment   = ..Default
]

---
DYNAMIC LISTS
---

DynamicList<t> : Abstract = [
    append(_, _.type)
    insert(_, _.type, Index)
    remove(_, Index)
]

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
    ._data      : &HeapMemory  -- Darle una vuelta a como se gestiona esto.
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

