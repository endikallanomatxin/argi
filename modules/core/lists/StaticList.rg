StaticList<t: Type, n: Int> : abstract = []

List<t> canbe StaticList<t, _>


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

StaticList<t, n> canbe StackArray<t, n>

StaticArray<t, n> : Type = [
    ---
    A heap allocated static array
    ---
    ._data      : HeapAllocation
    ._data_type : Type        = t
    ._length    : Int         = n
    ._alignment : Alignment   = ..Default
]

StaticList<t, n> canbe StaticArray<t, n>
