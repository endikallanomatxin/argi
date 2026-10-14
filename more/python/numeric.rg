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
        .result : Errable#(Object, (..python_error))
    ) := {
    assume ffi := self&._ffi
    count ::= length(&values).count
    address :: UIntNative = 0

    if count != 0 { address = data(.self = &values).pointer | convert#(.to: UIntNative)(_) }

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
        .result : Errable#(UIntNative, (..python_error))
    ) := {
    assume ffi := self&._python&._ffi
    capacity ::= length(&destination).count
    address :: UIntNative = 0

    if capacity != 0 { address = data(.self = &destination).pointer | convert#(.to: UIntNative)(_) }
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
        .result : Errable#(Object, (..python_error))
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

-- Element metadata selects the native format; view mutability stays explicit.
_PythonNumericScalar#(.Value: Type): Contract = (
    .native_kind: () -> (.value: Int32)
    .dtype: () -> (.value: StringView)
)
_PythonNumericView#(.View: Type): Contract = (
    .Element: Type
)
implement#(.t: Type: _PythonNumericScalar#(t)) _PythonNumericView#(ArrayView#(.t: t)) (.Element: Type = t)
implement#(.t: Type: _PythonNumericScalar#(t)) _PythonNumericView#(ArrayViewRO#(.t: t)) (.Element: Type = t)

numeric_buffer#(.View: Type: _PythonNumericView#(View)) := (
    .self: &Python, .values: View
) -> (.result: Errable#(Object, (..python_error))) {
    result = ~_array_storage#(.t: _PythonNumericView#(View).Element)(.self = self, .values = values)
}
numeric_array#(.View: Type: _PythonNumericView#(View)) := (
    .self: &Python, .values: View
) -> (.result: Errable#(Object, (..python_error))) {
    storage ::= numeric_buffer(.self = self, .values = values)!
    result = ~_numpy_array(.self = self, .storage = &storage, .dtype = _PythonNumericScalar#(_PythonNumericView#(View).Element).dtype())
}
copy_numeric#(.t: Type: _PythonNumericScalar#(t)) := (
    .self: &Object, .destination: ArrayView#(.t: t)
) -> (.result: Errable#(UIntNative, (..python_error))) {
    result = _copy_numeric(.self = self, .destination = destination, .kind = _PythonNumericScalar#(t).native_kind())
}

implement _PythonNumericScalar#(Int8) (
    .native_kind = () -> (.value: Int32) { value = 0 }
    .dtype = () -> (.value: StringView) { value = "=i1" }
)
implement _PythonNumericScalar#(Int16) (
    .native_kind = () -> (.value: Int32) { value = 0 }
    .dtype = () -> (.value: StringView) { value = "=i2" }
)
implement _PythonNumericScalar#(Int32) (
    .native_kind = () -> (.value: Int32) { value = 0 }
    .dtype = () -> (.value: StringView) { value = "=i4" }
)
implement _PythonNumericScalar#(Int64) (
    .native_kind = () -> (.value: Int32) { value = 0 }
    .dtype = () -> (.value: StringView) { value = "=i8" }
)
implement _PythonNumericScalar#(UInt8) (
    .native_kind = () -> (.value: Int32) { value = 1 }
    .dtype = () -> (.value: StringView) { value = "=u1" }
)
implement _PythonNumericScalar#(UInt16) (
    .native_kind = () -> (.value: Int32) { value = 1 }
    .dtype = () -> (.value: StringView) { value = "=u2" }
)
implement _PythonNumericScalar#(UInt32) (
    .native_kind = () -> (.value: Int32) { value = 1 }
    .dtype = () -> (.value: StringView) { value = "=u4" }
)
implement _PythonNumericScalar#(UInt64) (
    .native_kind = () -> (.value: Int32) { value = 1 }
    .dtype = () -> (.value: StringView) { value = "=u8" }
)
implement _PythonNumericScalar#(UIntNative) (
    .native_kind = () -> (.value: Int32) { value = 1 }
    .dtype = _native_dtype
)
implement _PythonNumericScalar#(Float32) (
    .native_kind = () -> (.value: Int32) { value = 2 }
    .dtype = () -> (.value: StringView) { value = "=f4" }
)
implement _PythonNumericScalar#(Float64) (
    .native_kind = () -> (.value: Int32) { value = 2 }
    .dtype = () -> (.value: StringView) { value = "=f8" }
)
