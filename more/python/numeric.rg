-- Bulk transfer copies initialized storage across the boundary. The Python
-- bytearray owner is independent of the input view; output views remain Argi
-- owners and are never fabricated from a foreign buffer address.
_numeric_storage(
        .context  : UIntNative,
        .source   : RawPointer#(.t: UInt8),
        .count    : UIntNative,
        .itemsize : UIntNative
    ) -> (
        .handle : RawPointer#(.t: _PyObject)
    ): CFunction(.symbol = "_argi_python_numeric_storage")

_buffer_copy(
        .context     : UIntNative,
        .object      : RawPointer#(.t: _PyObject),
        .destination : RawPointer#(.t: UInt8),
        .capacity    : UIntNative,
        .itemsize    : UIntNative,
        .kind        : Int32,

        .copied : $&UIntNative
    ) -> (
        .status : Int32
    ): CFunction(.symbol = "_argi_python_buffer_copy")

_array_storage#(
        .t         : Type,
        .view_type : Type
    )(
        .self   : &Python,
        .values : view_type
    ) -> (
        .result : Errable#(
            .t : Object,

            .reasons : (..python_error)
        )
    ) := {
    assume ffi := self&._ffi
    count ::= length(&values).count
    address :: UIntNative = 0

    if count != 0 { address = UIntNative(.value = data(.self = &values).pointer) }

    result = _owned(
        .self   = self
        .handle = _numeric_storage(
            .context  = self&._handle
            .source   = raw_pointer#(.t: UInt8)(.address = address).raw
            .count    = count
            .itemsize = size_of(.type = t)
        ).handle
    )
}

_copy_numeric#(
        .t : Type
    )(
        .self        : &Object,
        .destination : ArrayView#(.t: t),
        .kind        : Int32
    ) -> (
        .result : Errable#(
            .t : UIntNative,

            .reasons : (..python_error)
        )
    ) := {
    assume ffi := self&._python&._ffi
    capacity ::= length(&destination).count
    address :: UIntNative = 0

    if capacity != 0 { address = UIntNative(.value = data(.self = &destination).pointer) }
    copied :: UIntNative = 0

    if [
        _buffer_copy(
            .context     = self&._python&._handle
            .object      = self&._handle
            .destination = raw_pointer#(.t: UInt8)(.address = address).raw
            .capacity    = capacity
            .itemsize    = size_of(.type = t)
            .kind        = kind
            .copied      = $&copied
        ).status
        != 0
    ] {
        result = ..error(.reason = ..python_error)
        return
    }

    result = ..ok copied
}

_numpy_array(
        .self    : &Python,
        .storage : &Object,
        .dtype   : StringView
    ) -> (
        .result : Errable#(
            .t : Object,

            .reasons : (..python_error)
        )
    ) := {
    numpy ::= import_module(.self = self, .name = "numpy")!
    dtype_object ::= string(.self = self, .value = dtype)!
    arguments: [1]&Object = (storage)
    named: [1]Keyword = ((.name = "dtype", .value = &dtype_object))
    keywords ::= keyword_arguments(.self = self, .values = view(&named))!

    result = call_method(
        .self      = &numpy
        .name      = "frombuffer"
        .arguments = view(&arguments)
        .keywords  = ..some(.value = &keywords)
    )
}

_native_dtype() -> (.value: StringView) := {
    if size_of(.type = UIntNative) == 4 { value = "=u4" } else { value = "=u8" }
}

numeric_buffer(
        .self   : &Python,
        .values : ArrayViewRO#(.t: Int8)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    result = _array_storage#(.t: Int8)(.self = self, .values = values)
}

numeric_array(
        .self   : &Python,
        .values : ArrayViewRO#(.t: Int8)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    storage ::= numeric_buffer(.self = self, .values = values)!

    result = _numpy_array(.self = self, .storage = &storage, .dtype = "=i1")
}

numeric_buffer(
        .self   : &Python,
        .values : ArrayView#(.t: Int8)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    result = _array_storage#(.t: Int8)(.self = self, .values = values)
}

numeric_array(
        .self   : &Python,
        .values : ArrayView#(.t: Int8)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    storage ::= numeric_buffer(.self = self, .values = values)!

    result = _numpy_array(.self = self, .storage = &storage, .dtype = "=i1")
}

copy_numeric(
        .self        : &Object,
        .destination : ArrayView#(.t: Int8)
    ) -> (
        .result : Errable#(
            .t : UIntNative,

            .reasons : (..python_error)
        )
    ) := {
    result = _copy_numeric(.self = self, .destination = destination, .kind = 0)
}

numeric_buffer(
        .self   : &Python,
        .values : ArrayViewRO#(.t: Int16)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    result = _array_storage#(.t: Int16)(.self = self, .values = values)
}

numeric_array(
        .self   : &Python,
        .values : ArrayViewRO#(.t: Int16)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    storage ::= numeric_buffer(.self = self, .values = values)!

    result = _numpy_array(.self = self, .storage = &storage, .dtype = "=i2")
}

numeric_buffer(
        .self   : &Python,
        .values : ArrayView#(.t: Int16)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    result = _array_storage#(.t: Int16)(.self = self, .values = values)
}

numeric_array(
        .self   : &Python,
        .values : ArrayView#(.t: Int16)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    storage ::= numeric_buffer(.self = self, .values = values)!

    result = _numpy_array(.self = self, .storage = &storage, .dtype = "=i2")
}

copy_numeric(
        .self        : &Object,
        .destination : ArrayView#(.t: Int16)
    ) -> (
        .result : Errable#(
            .t : UIntNative,

            .reasons : (..python_error)
        )
    ) := {
    result = _copy_numeric(.self = self, .destination = destination, .kind = 0)
}

numeric_buffer(
        .self   : &Python,
        .values : ArrayViewRO#(.t: Int32)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    result = _array_storage#(.t: Int32)(.self = self, .values = values)
}

numeric_array(
        .self   : &Python,
        .values : ArrayViewRO#(.t: Int32)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    storage ::= numeric_buffer(.self = self, .values = values)!

    result = _numpy_array(.self = self, .storage = &storage, .dtype = "=i4")
}

numeric_buffer(
        .self   : &Python,
        .values : ArrayView#(.t: Int32)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    result = _array_storage#(.t: Int32)(.self = self, .values = values)
}

numeric_array(
        .self   : &Python,
        .values : ArrayView#(.t: Int32)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    storage ::= numeric_buffer(.self = self, .values = values)!

    result = _numpy_array(.self = self, .storage = &storage, .dtype = "=i4")
}

copy_numeric(
        .self        : &Object,
        .destination : ArrayView#(.t: Int32)
    ) -> (
        .result : Errable#(
            .t : UIntNative,

            .reasons : (..python_error)
        )
    ) := {
    result = _copy_numeric(.self = self, .destination = destination, .kind = 0)
}

numeric_buffer(
        .self   : &Python,
        .values : ArrayViewRO#(.t: Int64)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    result = _array_storage#(.t: Int64)(.self = self, .values = values)
}

numeric_array(
        .self   : &Python,
        .values : ArrayViewRO#(.t: Int64)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    storage ::= numeric_buffer(.self = self, .values = values)!

    result = _numpy_array(.self = self, .storage = &storage, .dtype = "=i8")
}

numeric_buffer(
        .self   : &Python,
        .values : ArrayView#(.t: Int64)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    result = _array_storage#(.t: Int64)(.self = self, .values = values)
}

numeric_array(
        .self   : &Python,
        .values : ArrayView#(.t: Int64)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    storage ::= numeric_buffer(.self = self, .values = values)!

    result = _numpy_array(.self = self, .storage = &storage, .dtype = "=i8")
}

copy_numeric(
        .self        : &Object,
        .destination : ArrayView#(.t: Int64)
    ) -> (
        .result : Errable#(
            .t : UIntNative,

            .reasons : (..python_error)
        )
    ) := {
    result = _copy_numeric(.self = self, .destination = destination, .kind = 0)
}

numeric_buffer(
        .self   : &Python,
        .values : ArrayViewRO#(.t: UInt8)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    result = _array_storage#(.t: UInt8)(.self = self, .values = values)
}

numeric_array(
        .self   : &Python,
        .values : ArrayViewRO#(.t: UInt8)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    storage ::= numeric_buffer(.self = self, .values = values)!

    result = _numpy_array(.self = self, .storage = &storage, .dtype = "=u1")
}

numeric_buffer(
        .self   : &Python,
        .values : ArrayView#(.t: UInt8)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    result = _array_storage#(.t: UInt8)(.self = self, .values = values)
}

numeric_array(
        .self   : &Python,
        .values : ArrayView#(.t: UInt8)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    storage ::= numeric_buffer(.self = self, .values = values)!

    result = _numpy_array(.self = self, .storage = &storage, .dtype = "=u1")
}

copy_numeric(
        .self        : &Object,
        .destination : ArrayView#(.t: UInt8)
    ) -> (
        .result : Errable#(
            .t : UIntNative,

            .reasons : (..python_error)
        )
    ) := {
    result = _copy_numeric(.self = self, .destination = destination, .kind = 1)
}

numeric_buffer(
        .self   : &Python,
        .values : ArrayViewRO#(.t: UInt16)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    result = _array_storage#(.t: UInt16)(.self = self, .values = values)
}

numeric_array(
        .self   : &Python,
        .values : ArrayViewRO#(.t: UInt16)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    storage ::= numeric_buffer(.self = self, .values = values)!

    result = _numpy_array(.self = self, .storage = &storage, .dtype = "=u2")
}

numeric_buffer(
        .self   : &Python,
        .values : ArrayView#(.t: UInt16)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    result = _array_storage#(.t: UInt16)(.self = self, .values = values)
}

numeric_array(
        .self   : &Python,
        .values : ArrayView#(.t: UInt16)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    storage ::= numeric_buffer(.self = self, .values = values)!

    result = _numpy_array(.self = self, .storage = &storage, .dtype = "=u2")
}

copy_numeric(
        .self        : &Object,
        .destination : ArrayView#(.t: UInt16)
    ) -> (
        .result : Errable#(
            .t : UIntNative,

            .reasons : (..python_error)
        )
    ) := {
    result = _copy_numeric(.self = self, .destination = destination, .kind = 1)
}

numeric_buffer(
        .self   : &Python,
        .values : ArrayViewRO#(.t: UInt32)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    result = _array_storage#(.t: UInt32)(.self = self, .values = values)
}

numeric_array(
        .self   : &Python,
        .values : ArrayViewRO#(.t: UInt32)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    storage ::= numeric_buffer(.self = self, .values = values)!

    result = _numpy_array(.self = self, .storage = &storage, .dtype = "=u4")
}

numeric_buffer(
        .self   : &Python,
        .values : ArrayView#(.t: UInt32)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    result = _array_storage#(.t: UInt32)(.self = self, .values = values)
}

numeric_array(
        .self   : &Python,
        .values : ArrayView#(.t: UInt32)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    storage ::= numeric_buffer(.self = self, .values = values)!

    result = _numpy_array(.self = self, .storage = &storage, .dtype = "=u4")
}

copy_numeric(
        .self        : &Object,
        .destination : ArrayView#(.t: UInt32)
    ) -> (
        .result : Errable#(
            .t : UIntNative,

            .reasons : (..python_error)
        )
    ) := {
    result = _copy_numeric(.self = self, .destination = destination, .kind = 1)
}

numeric_buffer(
        .self   : &Python,
        .values : ArrayViewRO#(.t: UInt64)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    result = _array_storage#(.t: UInt64)(.self = self, .values = values)
}

numeric_array(
        .self   : &Python,
        .values : ArrayViewRO#(.t: UInt64)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    storage ::= numeric_buffer(.self = self, .values = values)!

    result = _numpy_array(.self = self, .storage = &storage, .dtype = "=u8")
}

numeric_buffer(
        .self   : &Python,
        .values : ArrayView#(.t: UInt64)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    result = _array_storage#(.t: UInt64)(.self = self, .values = values)
}

numeric_array(
        .self   : &Python,
        .values : ArrayView#(.t: UInt64)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    storage ::= numeric_buffer(.self = self, .values = values)!

    result = _numpy_array(.self = self, .storage = &storage, .dtype = "=u8")
}

copy_numeric(
        .self        : &Object,
        .destination : ArrayView#(.t: UInt64)
    ) -> (
        .result : Errable#(
            .t : UIntNative,

            .reasons : (..python_error)
        )
    ) := {
    result = _copy_numeric(.self = self, .destination = destination, .kind = 1)
}

numeric_buffer(
        .self   : &Python,
        .values : ArrayViewRO#(.t: UIntNative)
    ) -> (
        .result : Errable#(
            .t : Object,

            .reasons : (..python_error)
        )
    ) := {
    result = _array_storage#(.t: UIntNative)(.self = self, .values = values)
}

numeric_array(
        .self   : &Python,
        .values : ArrayViewRO#(.t: UIntNative)
    ) -> (
        .result : Errable#(
            .t : Object,

            .reasons : (..python_error)
        )
    ) := {
    storage ::= numeric_buffer(.self = self, .values = values)!

    result = _numpy_array(.self = self, .storage = &storage, .dtype = _native_dtype().value)
}

numeric_buffer(
        .self   : &Python,
        .values : ArrayView#(.t: UIntNative)
    ) -> (
        .result : Errable#(
            .t : Object,

            .reasons : (..python_error)
        )
    ) := {
    result = _array_storage#(.t: UIntNative)(.self = self, .values = values)
}

numeric_array(
        .self   : &Python,
        .values : ArrayView#(.t: UIntNative)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    storage ::= numeric_buffer(.self = self, .values = values)!

    result = _numpy_array(.self = self, .storage = &storage, .dtype = _native_dtype().value)
}

copy_numeric(
        .self        : &Object,
        .destination : ArrayView#(.t: UIntNative)
    ) -> (
        .result : Errable#(
            .t : UIntNative,

            .reasons : (..python_error)
        )
    ) := {
    result = _copy_numeric(.self = self, .destination = destination, .kind = 1)
}

numeric_buffer(
        .self   : &Python,
        .values : ArrayViewRO#(.t: Float32)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    result = _array_storage#(.t: Float32)(.self = self, .values = values)
}

numeric_array(
        .self   : &Python,
        .values : ArrayViewRO#(.t: Float32)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    storage ::= numeric_buffer(.self = self, .values = values)!

    result = _numpy_array(.self = self, .storage = &storage, .dtype = "=f4")
}

numeric_buffer(
        .self   : &Python,
        .values : ArrayView#(.t: Float32)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    result = _array_storage#(.t: Float32)(.self = self, .values = values)
}

numeric_array(
        .self   : &Python,
        .values : ArrayView#(.t: Float32)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    storage ::= numeric_buffer(.self = self, .values = values)!

    result = _numpy_array(.self = self, .storage = &storage, .dtype = "=f4")
}

copy_numeric(
        .self        : &Object,
        .destination : ArrayView#(.t: Float32)
    ) -> (
        .result : Errable#(
            .t : UIntNative,

            .reasons : (..python_error)
        )
    ) := {
    result = _copy_numeric(.self = self, .destination = destination, .kind = 2)
}

numeric_buffer(
        .self   : &Python,
        .values : ArrayViewRO#(.t: Float64)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    result = _array_storage#(.t: Float64)(.self = self, .values = values)
}

numeric_array(
        .self   : &Python,
        .values : ArrayViewRO#(.t: Float64)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    storage ::= numeric_buffer(.self = self, .values = values)!

    result = _numpy_array(.self = self, .storage = &storage, .dtype = "=f8")
}

numeric_buffer(
        .self   : &Python,
        .values : ArrayView#(.t: Float64)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    result = _array_storage#(.t: Float64)(.self = self, .values = values)
}

numeric_array(
        .self   : &Python,
        .values : ArrayView#(.t: Float64)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    storage ::= numeric_buffer(.self = self, .values = values)!

    result = _numpy_array(.self = self, .storage = &storage, .dtype = "=f8")
}

copy_numeric(
        .self        : &Object,
        .destination : ArrayView#(.t: Float64)
    ) -> (
        .result : Errable#(
            .t : UIntNative,

            .reasons : (..python_error)
        )
    ) := {
    result = _copy_numeric(.self = self, .destination = destination, .kind = 2)
}
