# Collection types

The only non-library collection types are Arrays. The rest are structs defined
in the core library.

> [!NOTE] Why cannot arrays be defined in the core library? I've tried, but it
> seems that implementing them always requires some kind of `[]Byte` buffer.
> LLVM already has a `[N x %T]` type, that has some checks and information for
> optimizations. It is best to use it directly.

Available literals:

- List literals

    ```
    l := (1, 2, 3)
    ```

    They can convert into:

    - Array literals:
	- Arrays if constant
	- DynamicArrays if variable
	(mierda, necesitamos un allocator, así que igual siempre static y si
	quieres dynamic usas el constructor)

    - Struct literals


- Map literals

    ```
    m := ("a"=1, "b"=2)
    ```

