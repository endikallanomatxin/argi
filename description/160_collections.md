# Collection types

The native collection type is the fixed array `[N]T`. There is no native slice
type; other collections, including views, are library types.

Native arrays have a fixed extent in the type. Library collections can build
on this representation and provide views or dynamic storage separately.

Available literals:

- List literals

    ```
    l := (1, 2, 3)
    ```

    They can convert into:

    - Array literals:
	- Arrays if constant
	- DynamicArrays if variable
	(An allocator is required; perhaps collections should always be static, and
	users should use a constructor when dynamic storage is needed.)

The intended default heap-backed resizable list in `core` is `DynamicArray`.

    - Struct literals


- Map literals

    ```
    m := ("a"=1, "b"=2)
    ```
