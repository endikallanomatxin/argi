-- Python objects retain a borrow of their interpreter; cleanup releases each
-- owned reference before the interpreter is finalized. Native addresses never
-- become Argi safe references.
_PyObject: CIncomplete

Python: Type = (._handle: UIntNative, ._ffi: $&ForeignFunctionInterface)

Object: Type = (._handle: RawPointer#(.t: _PyObject), ._python: &Python)

..python_error
..python_initialization_failed

_start(
        .program        : &UInt8,
        .program_length : UIntNative,
        .home           : &UInt8,
        .home_length    : UIntNative
    ) -> (
        .handle : UIntNative
    ): CFunction(.symbol = "_argi_python_start")

_stop(.context: UIntNative) -> (.status: Int32): CFunction(.symbol = "_argi_python_stop")

_release(.context: UIntNative, .object: RawPointer#(.t: _PyObject)) -> (): CFunction(
    .symbol = "_argi_python_release"
)

_clone(
        .context : UIntNative,
        .object  : RawPointer#(.t: _PyObject)
    ) -> (
        .handle : RawPointer#(.t: _PyObject)
    ): CFunction(.symbol = "_argi_python_clone")

_import(
        .context : UIntNative,
        .bytes   : &UInt8,
        .length  : UIntNative
    ) -> (
        .handle : RawPointer#(.t: _PyObject)
    ): CFunction(.symbol = "_argi_python_import")

_attribute(
        .context : UIntNative,
        .object  : RawPointer#(.t: _PyObject),
        .bytes   : &UInt8,
        .length  : UIntNative
    ) -> (
        .handle : RawPointer#(.t: _PyObject)
    ): CFunction(.symbol = "_argi_python_attribute")

_string(
        .context : UIntNative,
        .bytes   : &UInt8,
        .length  : UIntNative
    ) -> (
        .handle : RawPointer#(.t: _PyObject)
    ): CFunction(.symbol = "_argi_python_string")

_bytes(
        .context : UIntNative,
        .bytes   : &UInt8,
        .length  : UIntNative
    ) -> (
        .handle : RawPointer#(.t: _PyObject)
    ): CFunction(.symbol = "_argi_python_bytes")

_scalar(
        .context  : UIntNative,
        .kind     : Int32,
        .signed   : Int64,
        .unsigned : UInt64,
        .floating : Float64
    ) -> (
        .handle : RawPointer#(.t: _PyObject)
    ): CFunction(.symbol = "_argi_python_scalar")

_get_item(
        .context : UIntNative,
        .object  : RawPointer#(.t: _PyObject),
        .key     : RawPointer#(.t: _PyObject)
    ) -> (
        .handle : RawPointer#(.t: _PyObject)
    ): CFunction(.symbol = "_argi_python_get_item")

_tuple(.context: UIntNative, .length: UIntNative) -> (.handle: RawPointer#(.t: _PyObject)): CFunction(
    .symbol = "_argi_python_tuple"
)

_call(
        .context   : UIntNative,
        .object    : RawPointer#(.t: _PyObject),
        .arguments : RawPointer#(.t: _PyObject),
        .keywords  : RawPointer#(.t: _PyObject)
    ) -> (
        .handle : RawPointer#(.t: _PyObject)
    ): CFunction(.symbol = "_argi_python_call")

_repr(
        .context : UIntNative,
        .object  : RawPointer#(.t: _PyObject)
    ) -> (
        .handle : RawPointer#(.t: _PyObject)
    ): CFunction(.symbol = "_argi_python_repr")

_int64(
        .context : UIntNative,
        .object  : RawPointer#(.t: _PyObject),
        .value   : $&Int64
    ) -> (
        .status : Int32
    ): CFunction(.symbol = "_argi_python_int64")

_uint64(
        .context : UIntNative,
        .object  : RawPointer#(.t: _PyObject),
        .value   : $&UInt64
    ) -> (
        .status : Int32
    ): CFunction(.symbol = "_argi_python_uint64")

_float64(
        .context : UIntNative,
        .object  : RawPointer#(.t: _PyObject),
        .value   : $&Float64
    ) -> (
        .status : Int32
    ): CFunction(.symbol = "_argi_python_float64")

_tuple_set(
        .context : UIntNative,
        .tuple   : RawPointer#(.t: _PyObject),
        .index   : UIntNative,
        .object  : RawPointer#(.t: _PyObject)
    ) -> (
        .status : Int32
    ): CFunction(.symbol = "_argi_python_tuple_set")

Python init(
        .ffi          : $&ForeignFunctionInterface,
        .program_name : StringView                  = "python3",
        .home         : StringView                  = ""
    ) -> (
        .result : Errable#(
            .t       : Python,
            .reasons : (..python_initialization_failed)
        )
    ) := {
    assume ffi
    handle ::= _start(
        .program        = program_name.data
        .program_length = program_name.length
        .home           = home.data
        .home_length    = home.length
    ).handle
    if handle == 0 {
        result = ..error(.reason = ..python_initialization_failed)
        return
    }
    result = ..ok(._handle = handle, ._ffi = ffi)
}

Python deinit(.self: $&Python) -> () := {
    assume ffi := self&._ffi
    _stop(.context = self&._handle)
}

Object deinit(.self: $&Object) -> () := {
    assume ffi := self&._python&._ffi
    _release(.context = self&._python&._handle, .object = self&._handle)
}

_owned(
        .self   : &Python,
        .handle : RawPointer#(.t: _PyObject)
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    if handle.address == 0 {
        result = ..error(.reason = ..python_error)
        return
    }
    result = ..ok(._handle = handle, ._python = self)
}

import_module(
        .self : &Python,
        .name : StringView
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    assume ffi := self&._ffi
    result = _owned(
        .self   = self
        .handle = _import(.context = self&._handle, .bytes = name.data, .length = name.length).handle
    )
}

string(
        .self  : &Python,
        .value : StringView
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    assume ffi := self&._ffi
    result = _owned(
        .self   = self
        .handle = _string(.context = self&._handle, .bytes = value.data, .length = value.length).handle
    )
}

bytes(
        .self  : &Python,
        .value : StringView
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    assume ffi := self&._ffi
    result = _owned(
        .self   = self
        .handle = _bytes(.context = self&._handle, .bytes = value.data, .length = value.length).handle
    )
}

clone(.self: &Object) -> (.result: Errable#(.t: Object, .reasons: (..python_error))) := {
    assume ffi := self&._python&._ffi
    result = _owned(
        .self   = self&._python
        .handle = _clone(.context = self&._python&._handle, .object = self&._handle).handle
    )
}

attribute(
        .self : &Object,
        .name : StringView
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    assume ffi := self&._python&._ffi
    result = _owned(
        .self   = self&._python
        .handle = _attribute(
            .context = self&._python&._handle
            .object  = self&._handle
            .bytes   = name.data
            .length  = name.length
        ).handle
    )
}

get_item(
        .self : &Object,
        .key  : &Object
    ) -> (
        .result : Errable#(.t: Object, .reasons: (..python_error))
    ) := {
    assume ffi := self&._python&._ffi
    result = _owned(
        .self   = self&._python
        .handle = _get_item(
            .context = self&._python&._handle
            .object  = self&._handle
            .key     = key&._handle
        ).handle
    )
}

repr(.self: &Object) -> (.result: Errable#(.t: Object, .reasons: (..python_error))) := {
    assume ffi := self&._python&._ffi
    result = _owned(
        .self   = self&._python
        .handle = _repr(.context = self&._python&._handle, .object = self&._handle).handle
    )
}

to_int64(.self: &Object) -> (.result: Errable#(.t: Int64, .reasons: (..python_error))) := {
    assume ffi := self&._python&._ffi
    value :: Int64 = 0
    if [
        _int64(.context = self&._python&._handle, .object = self&._handle, .value = $&value).status
        != 0
    ] {
        result = ..error(.reason = ..python_error)
        return
    }
    result = ..ok value
}

to_uint64(.self: &Object) -> (.result: Errable#(.t: UInt64, .reasons: (..python_error))) := {
    assume ffi := self&._python&._ffi
    value :: UInt64 = 0
    if [
        _uint64(.context = self&._python&._handle, .object = self&._handle, .value = $&value).status
        != 0
    ] {
        result = ..error(.reason = ..python_error)
        return
    }
    result = ..ok value
}

to_float64(.self: &Object) -> (.result: Errable#(.t: Float64, .reasons: (..python_error))) := {
    assume ffi := self&._python&._ffi
    value :: Float64 = 0.0
    if [
        _float64(.context = self&._python&._handle, .object = self&._handle, .value = $&value).status
        != 0
    ] {
        result = ..error(.reason = ..python_error)
        return
    }
    result = ..ok value
}

_no_arguments() -> (.value: ArrayViewRO#(.t: &Object)) := { value = array_view_ro#(.t: &Object)() }

_no_keywords() -> (.value: ?&Object) := { value = ..none }

call(
        .self      : &Object,
        .arguments : ArrayViewRO#(.t: &Object) = _no_arguments(),
        .keywords  : ?&Object                  = _no_keywords()
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    assume ffi := self&._python&._ffi
    tuple ::= _tuple(.context = self&._python&._handle, .length = length(.self = &arguments).count).handle
    if tuple.address == 0 {
        result = ..error(.reason = ..python_error)
        return
    }
    index :: UIntNative = 0
    while index < length(.self = &arguments).count {
        argument ::= unwrap_or_abort(.value = get_ro_ref(.self = &arguments, .index = index)).result
        if [
            _tuple_set(
                .context = self&._python&._handle
                .tuple   = tuple
                .index   = index
                .object  = argument&&._handle
            ).status
            != 0
        ] {
            _release(.context = self&._python&._handle, .object = tuple)
            result = ..error(.reason = ..python_error)
            return
        }
        index = index + 1
    }
    keyword_handle :: RawPointer#(.t: _PyObject) = raw_pointer#(.t: _PyObject)(.address = 0).raw
    match keywords { ..some payload { keyword_handle = payload.value&._handle } ..none {} }
    handle ::= _call(
        .context   = self&._python&._handle
        .object    = self&._handle
        .arguments = tuple
        .keywords  = keyword_handle
    ).handle
    _release(.context = self&._python&._handle, .object = tuple)
    result = _owned(.self = self&._python, .handle = handle)
}

_bool(.context: UIntNative, .object: RawPointer#(.t: _PyObject)) -> (.status: Int32): CFunction(
    .symbol = "_argi_python_bool"
)

_is_none(.context: UIntNative, .object: RawPointer#(.t: _PyObject)) -> (.status: Int32): CFunction(
    .symbol = "_argi_python_is_none"
)

_size(
        .context : UIntNative,
        .object  : RawPointer#(.t: _PyObject),
        .length  : $&UIntNative
    ) -> (
        .status : Int32
    ): CFunction(.symbol = "_argi_python_size")

_append(
        .context : UIntNative,
        .object  : RawPointer#(.t: _PyObject),
        .value   : RawPointer#(.t: _PyObject)
    ) -> (
        .status : Int32
    ): CFunction(.symbol = "_argi_python_append")

_set_item(
        .context : UIntNative,
        .object  : RawPointer#(.t: _PyObject),
        .key     : RawPointer#(.t: _PyObject),
        .value   : RawPointer#(.t: _PyObject)
    ) -> (
        .status : Int32
    ): CFunction(.symbol = "_argi_python_set_item")

_text_size(
        .context : UIntNative,
        .object  : RawPointer#(.t: _PyObject),
        .kind    : Int32,
        .length  : $&UIntNative
    ) -> (
        .status : Int32
    ): CFunction(.symbol = "_argi_python_text_size")

_text_copy(
        .context     : UIntNative,
        .object      : RawPointer#(.t: _PyObject),
        .kind        : Int32,
        .destination : RawPointer#(.t: UInt8),
        .length      : UIntNative
    ) -> (
        .status : Int32
    ): CFunction(.symbol = "_argi_python_text_copy")

_error_size(.context: UIntNative) -> (.length: UIntNative): CFunction(
    .symbol = "_argi_python_error_size"
)

_error_copy(
        .context     : UIntNative,
        .destination : RawPointer#(.t: UInt8),
        .length      : UIntNative
    ) -> (
        .status : Int32
    ): CFunction(.symbol = "_argi_python_error_copy")

none(.self: &Python) -> (.result: Errable#(.t: Object, .reasons: (..python_error))) := {
    assume ffi := self&._ffi
    result = _owned(
        .self   = self
        .handle = _scalar(
            .context  = self&._handle
            .kind     = 0
            .signed   = _zero_signed().value
            .unsigned = _zero_unsigned().value
            .floating = _zero_float().value
        ).handle
    )
}

boolean(
        .self  : &Python,
        .value : Bool
    ) -> (
        .result : Errable#(.t: Object, .reasons: (..python_error))
    ) := {
    assume ffi := self&._ffi
    result = _owned(
        .self   = self
        .handle = _scalar(
            .context  = self&._handle
            .kind     = 1
            .signed   = _boolean_int(.value = value).number
            .unsigned = _zero_unsigned().value
            .floating = _zero_float().value
        ).handle
    )
}

integer(
        .self  : &Python,
        .value : Int64
    ) -> (
        .result : Errable#(.t: Object, .reasons: (..python_error))
    ) := {
    assume ffi := self&._ffi
    result = _owned(
        .self   = self
        .handle = _scalar(
            .context  = self&._handle
            .kind     = 2
            .signed   = value
            .unsigned = _zero_unsigned().value
            .floating = _zero_float().value
        ).handle
    )
}

integer(
        .self  : &Python,
        .value : UInt64
    ) -> (
        .result : Errable#(.t: Object, .reasons: (..python_error))
    ) := {
    assume ffi := self&._ffi
    result = _owned(
        .self   = self
        .handle = _scalar(
            .context  = self&._handle
            .kind     = 3
            .signed   = _zero_signed().value
            .unsigned = value
            .floating = _zero_float().value
        ).handle
    )
}

floating(
        .self  : &Python,
        .value : Float64
    ) -> (
        .result : Errable#(
            .t       : Object,
            .reasons : (..python_error)
        )
    ) := {
    assume ffi := self&._ffi
    result = _owned(
        .self   = self
        .handle = _scalar(
            .context  = self&._handle
            .kind     = 4
            .signed   = _zero_signed().value
            .unsigned = _zero_unsigned().value
            .floating = value
        ).handle
    )
}

list(.self: &Python) -> (.result: Errable#(.t: Object, .reasons: (..python_error))) := {
    assume ffi := self&._ffi
    result = _owned(
        .self   = self
        .handle = _scalar(
            .context  = self&._handle
            .kind     = 5
            .signed   = _zero_signed().value
            .unsigned = _zero_unsigned().value
            .floating = _zero_float().value
        ).handle
    )
}

dictionary(.self: &Python) -> (.result: Errable#(.t: Object, .reasons: (..python_error))) := {
    assume ffi := self&._ffi
    result = _owned(
        .self   = self
        .handle = _scalar(
            .context  = self&._handle
            .kind     = 6
            .signed   = _zero_signed().value
            .unsigned = _zero_unsigned().value
            .floating = _zero_float().value
        ).handle
    )
}

_boolean_int(.value: Bool) -> (.number: Int64) := { if value { number = 1 } else { number = 0 } }

to_bool(.self: &Object) -> (.result: Errable#(.t: Bool, .reasons: (..python_error))) := {
    assume ffi := self&._python&._ffi
    status ::= _bool(.context = self&._python&._handle, .object = self&._handle).status
    if status < 0 {
        result = ..error(.reason = ..python_error)
        return
    }
    value: Bool = status == 1
    result = ..ok value
}

is_none(.self: &Object) -> (.result: Errable#(.t: Bool, .reasons: (..python_error))) := {
    assume ffi := self&._python&._ffi
    status ::= _is_none(.context = self&._python&._handle, .object = self&._handle).status
    if status < 0 {
        result = ..error(.reason = ..python_error)
        return
    }
    value: Bool = status == 1
    result = ..ok value
}

length(.self: &Object) -> (.result: Errable#(.t: UIntNative, .reasons: (..python_error))) := {
    assume ffi := self&._python&._ffi
    count :: UIntNative = 0
    if [
        _size(.context = self&._python&._handle, .object = self&._handle, .length = $&count).status
        != 0
    ] {
        result = ..error(.reason = ..python_error)
        return
    }
    result = ..ok count
}

append(
        .self  : &Object,
        .value : &Object
    ) -> (
        .result : Errable#(.t: Void, .reasons: (..python_error))
    ) := {
    assume ffi := self&._python&._ffi
    if [
        _append(
            .context = self&._python&._handle
            .object  = self&._handle
            .value   = value&._handle
        ).status
        != 0
    ] {
        result = ..error(.reason = ..python_error)
        return
    }
    result = ..ok Void()
}

set_item(
        .self  : &Object,
        .key   : &Object,
        .value : &Object
    ) -> (
        .result : Errable#(
            .t       : Void,
            .reasons : (..python_error)
        )
    ) := {
    assume ffi := self&._python&._ffi
    if [
        _set_item(
            .context = self&._python&._handle
            .object  = self&._handle
            .key     = key&._handle
            .value   = value&._handle
        ).status
        != 0
    ] {
        result = ..error(.reason = ..python_error)
        return
    }
    result = ..ok Void()
}

_copy_text(
        .self      : &Object,
        .kind      : Int32,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(
            .t       : String,
            .reasons : (..python_error, ..out_of_memory)
        )
    ) := {
    assume ffi := self&._python&._ffi
    count :: UIntNative = 0
    if [
        _text_size(
            .context = self&._python&._handle
            .object  = self&._handle
            .kind    = kind
            .length  = $&count
        ).status
        != 0
    ] {
        result = ..error(.reason = ..python_error)
        return
    }
    text ::= string_with_length(.allocator = allocator, .length = count)!
    if [
        _text_copy(
            .context     = self&._python&._handle
            .object      = self&._handle
            .kind        = kind
            .destination = text.allocation.data
            .length      = count
        ).status
        != 0
    ] {
        result = ..error(.reason = ..python_error)
        return
    }
    result = ..ok ~text
}

to_string(
        .self      : &Object,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(
            .t       : String,
            .reasons : (..python_error, ..out_of_memory)
        )
    ) := {
    result = _copy_text(.self = self, .kind = 0, .allocator = allocator)
}

to_bytes(
        .self      : &Object,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(
            .t       : String,
            .reasons : (..python_error, ..out_of_memory)
        )
    ) := {
    result = _copy_text(.self = self, .kind = 1, .allocator = allocator)
}

error_text(
        .self      : &Python,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(
            .t       : String,
            .reasons : (..python_error, ..out_of_memory)
        )
    ) := {
    assume ffi := self&._ffi
    count ::= _error_size(.context = self&._handle).length
    text ::= string_with_length(.allocator = allocator, .length = count)!
    if [
        _error_copy(.context = self&._handle, .destination = text.allocation.data, .length = count).status
        != 0
    ] {
        result = ..error(.reason = ..python_error)
        return
    }
    result = ..ok ~text
}

_zero_signed() -> (.value: Int64) := { value = 0 }

_zero_unsigned() -> (.value: UInt64) := { value = 0 }

_zero_float() -> (.value: Float64) := { value = 0.0 }
