# Typed NumPy vectors

Import `python/numpy` for `Vector64`, an owning wrapper for one-dimensional
native-endian Float64 NumPy arrays. It is optional, like the underlying Python
embedding. Install NumPy in the selected Python environment and use the same
[preparation helper and native dependencies](../README.md).

```rg
python := import("python")
numpy := import("python/numpy")
main(.system: System) -> !Void = ..ok Void() := {
    interpreter ::= python.Python(.ffi = system.ffi)!
    values: [3]Float64 = (1.0, 2.0, 3.0)
    vector ::= numpy.Vector64(.interpreter = &interpreter,
        .values = view(.array = &values))!
    if numpy.dot(.left = &vector, .right = &vector)! != 14.0 { abort }
}
```

Construction copies the input into Python-owned storage. `add` and `multiply`
return independent vectors, `dot` and `sum` return Float64, and `length` reports
the fixed size. Binary operations require equal lengths; NumPy broadcasting is
not implicit in this API. Empty vectors have zero sum and dot product.

`copy_values(.self, .destination)` copies into an initialized mutable Float64
view and returns the count. It rejects a destination smaller than the vector
before writing; extra destination elements remain unchanged. Shape errors use
`numpy_shape_mismatch`; package/import/conversion failures retain Python's
ordinary `python_error` and exception snapshot mechanisms.

A vector owns its Python object and borrows its interpreter. It must obey that
interpreter's lifetime and thread restrictions, cannot be copied implicitly, and
supports ownership transfer with `~`. The object is private so arbitrary Python
calls cannot silently change the wrapper's dtype, shape, or length invariant.
There are no borrowed foreign buffers, shared Argi allocations, or callbacks.

Run the consumer with matching CPython development dependencies:

```sh
python3 more/python/build.py --argi zig-out/bin/argi run tests/feature_tests/python/13_numpy_vector
```

The optional Python smoke exercises it when passed `--numpy`. Compiler fixture
execution additionally requires `ARGI_PYTHON_NUMPY=1` alongside the ordinary
adapter/library paths. Negative copying, lifetime, and privacy fixtures need no
NumPy installation. Other dtypes, matrices, and package wrappers should follow
concrete consumers rather than expanding this wrapper's dynamic surface.
