StructOfArrays<t> : Type = [
    ---
    It behaves as an array-of-structs for the user but is implemented as a struct-of-arrays
    It allows for:
        - More compact memory layout, with less padding.
        - More efficient caching
    ---
    ._base_struct_type : Type = t
    ._arrays
    ...
]

init(#t :== List<t>, &l : List) {
    ...
}

operator get[] (&soa: StructOfArrays<t>, i: Index) {
    ---
    Return the struct that would be at position i
    ---
    ...
}

...

to_soa($&l: List<Struct>) {
    -- pensar en como referirnos a un tipo cualquiera que sea struct.
    -- It converts a list to a StructOfArrays
    ...
}
