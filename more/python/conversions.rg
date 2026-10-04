-- Conversion is an ordinary overload family, specialized for concrete inputs.
-- Container conversions copy elements into Python-owned storage and retain no
-- borrow of the source collection.
Keyword: Type = (.name: StringView, .value: &Object)
Keyword implements ImplicitlyCopyable
to_object(.self: &Python, .value: Int8) -> (.result: Errable#(.t: Object, .reasons: (..python_error))) := {
    result = integer(.self = self, .value = Int64(.value = value))
}
to_object(.self: &Python, .value: Int16) -> (.result: Errable#(.t: Object,
        .reasons : (..python_error))) := {
    result = integer(.self = self, .value = Int64(.value = value))
}
to_object(.self: &Python, .value: Int32) -> (.result: Errable#(.t: Object,
        .reasons : (..python_error))) := {
    result = integer(.self = self, .value = Int64(.value = value))
}
to_object(.self: &Python, .value: Int64) -> (.result: Errable#(.t: Object,
        .reasons : (..python_error))) := {
    result = integer(.self = self, .value = value)
}
to_object(.self: &Python, .value: UInt8) -> (.result: Errable#(.t: Object,
        .reasons : (..python_error))) := {
    result = integer(.self = self, .value = UInt64(.value = value))
}
to_object(.self: &Python, .value: UInt16) -> (.result: Errable#(.t: Object,
        .reasons : (..python_error))) := {
    result = integer(.self = self, .value = UInt64(.value = value))
}
to_object(.self: &Python, .value: UInt32) -> (.result: Errable#(.t: Object,
        .reasons : (..python_error))) := {
    result = integer(.self = self, .value = UInt64(.value = value))
}
to_object(.self: &Python, .value: UInt64) -> (.result: Errable#(.t: Object,
        .reasons : (..python_error))) := {
    result = integer(.self = self, .value = value)
}
to_object(.self: &Python, .value: UIntNative) -> (.result: Errable#(.t: Object,
        .reasons : (..python_error))) := {
    result = integer(.self = self, .value = UInt64(.value = value))
}
to_object(.self: &Python, .value: Bool) -> (.result: Errable#(.t: Object, .reasons: (..python_error))) := {
    result = boolean(.self = self, .value = value)
}
to_object(.self: &Python, .value: Float64) -> (.result: Errable#(.t: Object,
        .reasons : (..python_error))) := {
    result = floating(.self = self, .value = value)
}
to_object(.self: &Python, .value: StringView) -> (.result: Errable#(.t: Object,
        .reasons : (..python_error))) := {
    result = string(.self = self, .value = value)
}
to_object(.self: &Python, .value: &Object) -> (.result: Errable#(.t: Object,
        .reasons : (..python_error))) := {
    result = clone(.self = value)
}
to_object(.self: &Python, .value: &String) -> (.result: Errable#(.t: Object,
        .reasons : (..python_error))) := {
    result = string(.self = self, .value = as_view(.self = value).view)
}
to_object#(.t: Type)(.self: &Python, .value: ArrayViewRO#(.t: t)) -> (.result: Errable#(.t: Object,
        .reasons : (..python_error))) := {
    converted ::= list(.self = self)!
    index :: UIntNative = 0
    while index < length(.self = &value).count {
        source ::= unwrap_or_abort(.value = get_ro_ref(.self = &value, .index = index)).result
        element ::= to_object(.self = self, .value = source)!
        append(.self = &converted, .value = &element)!
        index = index + 1
    }
    result = ..ok ~converted
}
to_object#(.n: UIntNative, .t: Type)(.self: &Python, .value: &Array#(.n = n, .t: t)) -> (.result: Errable#(.t: Object,

        .reasons : (..python_error))) := {
    result = to_object(.self = self, .value = view(.array = value))
}
to_object#(.t: Type)(.self: &Python, .value: &DynamicArray#(.t: t)) -> (.result: Errable#(.t: Object,

        .reasons : (..python_error))) := {
    result = to_object(.self = self, .value = array_view_ro(.array = value).view)
}
keyword_arguments(.self: &Python, .values: ArrayViewRO#(.t: Keyword)) -> (.result: Errable#(.t: Object,

        .reasons : (..python_error))) := {
    converted ::= dictionary(.self = self)!
    index :: UIntNative = 0
    while index < length(.self = &values).count {
        entry ::= unwrap_or_abort(.value = get_ro_ref(.self = &values, .index = index)).result
        key ::= string(.self = self, .value = entry&.name)!
        set_item(.self = &converted, .key = &key, .value = entry&.value)!
        index = index + 1
    }
    result = ..ok ~converted
}

to_object#(.t: Type: ImplicitlyCopyable)(.self: &Python, .value: &t) -> (.result: Errable#(.t: Object,

        .reasons : (..python_error))) := {
    result = to_object(.self = self, .value = value&)
}
_float32(.context: UIntNative, .value: Float32) -> (.handle: RawPointer#(.t: _PyObject)): CFunction(.symbol = "_argi_python_float32")
to_object(.self: &Python, .value: Float32) -> (.result: Errable#(.t: Object,
        .reasons : (..python_error))) := {
    assume ffi := self&._ffi
    result = _owned(.self = self,
        .handle = _float32(.context = self&._handle, .value = value).handle)
}
Argument: Type = (
    ..none
    ..boolean Bool
    ..integer Int64
    ..unsigned UInt64
    ..floating Float64
    ..text StringView
    ..object&Object
)
Argument implements ImplicitlyCopyable
NamedArgument: Type = (.name: StringView, .value: Argument)
NamedArgument implements ImplicitlyCopyable
to_object(.self: &Python, .value: Argument) -> (.result: Errable#(.t: Object,
        .reasons : (..python_error))) := {
    match value {
        ..none { result = none(.self = self) }
        ..boolean payload { result = boolean(.self = self, .value = payload) }
        ..integer payload { result = integer(.self = self, .value = payload) }
        ..unsigned payload { result = integer(.self = self, .value = payload) }
        ..floating payload { result = floating(.self = self, .value = payload) }
        ..text payload { result = string(.self = self, .value = payload) }
        ..object payload { result = clone(.self = payload) }
    }
}
keyword_arguments(.self: &Python, .values: ArrayViewRO#(.t: NamedArgument)) -> (.result: Errable#(.t: Object,

        .reasons : (..python_error))) := {
    converted ::= dictionary(.self = self)!
    index :: UIntNative = 0
    while index < length(.self = &values).count {
        entry ::= unwrap_or_abort(.value = get_ro_ref(.self = &values, .index = index)).result
        key ::= string(.self = self, .value = entry&.name)!
        value ::= to_object(.self = self, .value = entry&.value)!
        set_item(.self = &converted, .key = &key, .value = &value)!
        index = index + 1
    }
    result = ..ok ~converted
}
_as_tuple(.context: UIntNative, .value: RawPointer#(.t: _PyObject)) -> (.handle: RawPointer#(.t: _PyObject)): CFunction(.symbol = "_argi_python_as_tuple")
positional_arguments#(.t: Type)(.self: &Python, .values: ArrayViewRO#(.t: t)) -> (.result: Errable#(.t: Object,

        .reasons : (..python_error))) := {
    assume ffi := self&._ffi
    converted ::= to_object(.self = self, .value = values)!
    result = _owned(.self = self,
        .handle = _as_tuple(.context = self&._handle, .value = converted._handle).handle)
}
call(.self: &Object, .arguments: &Object, .keywords: ?&Object = _no_keywords()) -> (.result: Errable#(.t: Object,

        .reasons : (..python_error))) := {
    assume ffi := self&._python&._ffi
    keyword_handle :: RawPointer#(.t: _PyObject) = raw_pointer#(.t: _PyObject)(.address = 0).raw
    match keywords { ..some payload { keyword_handle = payload.value&._handle } ..none {} }
    handle ::= _call(.context = self&._python&._handle, .object = self&._handle,
        .arguments = arguments&._handle, .keywords = keyword_handle).handle
    result = _owned(.self = self&._python, .handle = handle)
}
to_object#(.t: Type)(.self: &Python, .value: ArrayView#(.t: t)) -> (.result: Errable#(.t: Object,
        .reasons : (..python_error))) := {
    converted ::= list(.self = self)!
    index :: UIntNative = 0
    while index < length(.self = &value).count {
        source ::= unwrap_or_abort(.value = get_ro_ref(.self = &value, .index = index)).result
        element ::= to_object(.self = self, .value = source)!
        append(.self = &converted, .value = &element)!
        index = index + 1
    }
    result = ..ok ~converted
}
