-- Owners preserve a checked row-major shape; no exported mutable shape fields.
DynamicMatrix := #(.t: Type: Scalar) (
    ._rows   : UIntNative,
    ._cols   : UIntNative,
    ._values : DynamicArray#(.t: t)
)

..dimension_mismatch

_extent := (.rows: UIntNative, .cols: UIntNative, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(UIntNative, (..dimension_mismatch))
) {
    assume error_tracer

    maximum ::= integer_limits(.value = rows).maximum

    if cols != 0 {
        if rows > maximum / cols {
            result = ..error(.reason = ..dimension_mismatch)
            return
        }
    }

    result = ..ok rows * cols
}

DynamicMatrixInitArgs: Type = #(.t: Type: Scalar, .Provider: Type: Allocator) (
    .rows         : UIntNative,
    .cols         : UIntNative,
    .values       : ArrayView#(.t: t),
    .allocator    : $&Provider,
    .error_tracer : $&Virtual#(ErrorTracer)
)

implement#(.t: Type: Scalar, .Provider: Type: Allocator) Init#(
    DynamicMatrix#(.t: t), DynamicMatrixInitArgs#(t, Provider)
) (
    .Result : Type = Errable#(DynamicMatrix#(.t: t), (..dimension_mismatch, ..out_of_memory))

    .init = DynamicMatrixInitArgs#(t, Provider) -> (.result: Result) {
        assume error_tracer

        _init_rows ::= rows
        _init_cols ::= cols
        _init_values ::= values
        _init_allocator ::= allocator

        count ::= _extent(.rows = _init_rows, .cols = _init_cols)!

        if count != length(&_init_values).count {
            result = ..error(.reason = ..dimension_mismatch)
            return
        }

        storage ::= DynamicArray#(.t: t)(.allocator = _init_allocator, .capacity = count)!
        i :: UIntNative = 0

        while i < count {
            item ::= unwrap_or_abort(.value = get(.self = &_init_values, .index = i)).result
            push(.self = $&storage, .value = item, .allocator = _init_allocator)!
            i = i + 1
        }

        result = ..ok(._rows = _init_rows, ._cols = _init_cols, ._values = ~storage)
    }
)

shape := #(.t: Type: Scalar) (.self: &DynamicMatrix#(.t: t)) -> (
    .rows: UIntNative, .cols: UIntNative
) {
    rows = self&._rows
    cols = self&._cols
}

_math_get_dynamic_matrix := #(.t: Type: Scalar) (
    .self         : &DynamicMatrix#(.t: t),
    .row          : UIntNative,
    .col          : UIntNative,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(t, (..out_of_bounds))) {
    assume error_tracer

    if row >= self&._rows or col >= self&._cols {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    result = get(.self = &self&._values, .index = row * self&._cols + col)
}

_math_set_dynamic_matrix := #(.t: Type: Scalar) (
    .self         : $&DynamicMatrix#(.t: t),
    .row          : UIntNative,
    .col          : UIntNative,
    .value        : t,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Void, (..out_of_bounds))) {
    assume error_tracer

    if row >= self&._rows or col >= self&._cols {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    pointer ::= get_mutable_reference(.self = $&self&._values, .index = row * self&._cols + col)!
    pointer&= value

    result = ..ok Void()
}

implement#(.t: Type: Scalar) Add#(&DynamicMatrix#(.t: t), &DynamicMatrix#(.t: t)) (
    .Result : Type = Errable#(DynamicMatrix#(.t: t), (..dimension_mismatch, ..out_of_memory))
    .add    = #(.Provider: Type: Allocator) (
        .left         : &DynamicMatrix#(.t: t),
        .right        : &DynamicMatrix#(.t: t),
        .allocator    : $&Provider,
        .error_tracer : $&Virtual#(ErrorTracer)
    ) -> (.result: Result) {
        assume error_tracer

        assume allocator

        if left&._rows != right&._rows or left&._cols != right&._cols {
            result = ..error(.reason = ..dimension_mismatch)
            return
        }

        count ::= length(&left&._values).count
        storage ::= DynamicArray#(.t: t)(.allocator = allocator, .capacity = count)!
        i :: UIntNative = 0

        while i < count {
            a ::= unwrap_or_abort(.value = get(.self = &left&._values, .index = i)).result
            b ::= unwrap_or_abort(.value = get(.self = &right&._values, .index = i)).result
            push(.self = $&storage, .value = a + b, .allocator = allocator)!
            i = i + 1
        }

        result = ..ok(._rows = left&._rows, ._cols = left&._cols, ._values = ~storage)
    }
)

implement#(.t: Type: Scalar) Multiply#(&DynamicMatrix#(.t: t), &DynamicMatrix#(.t: t)) (
    .Result   : Type = Errable#(DynamicMatrix#(.t: t), (..dimension_mismatch, ..out_of_memory))
    .multiply = #(.Provider: Type: Allocator) (
        .left         : &DynamicMatrix#(.t: t),
        .right        : &DynamicMatrix#(.t: t),
        .allocator    : $&Provider,
        .error_tracer : $&Virtual#(ErrorTracer)
    ) -> (.result: Result) {
        assume error_tracer

        assume allocator

        if left&._cols != right&._rows {
            result = ..error(.reason = ..dimension_mismatch)
            return
        }

        count ::= _extent(.rows = left&._rows, .cols = right&._cols)!
        storage ::= DynamicArray#(.t: t)(.allocator = allocator, .capacity = count)!

        if count == 0 {
            result = ..ok(._rows = left&._rows, ._cols = right&._cols, ._values = ~storage)
            return
        }

        row :: UIntNative = 0

        while row < left&._rows {
            col :: UIntNative = 0
            while col < right&._cols {
                sum ::= zeroed#(.t: t)().value
                k :: UIntNative = 0
                while k < left&._cols {
                    a ::= unwrap_or_abort(
                        .value = get(.self = left, .row = row, .col = k)
                    ).result
                    b ::= unwrap_or_abort(
                        .value = get(.self = right, .row = k, .col = col)
                    ).result
                    sum = sum + a * b
                    k = k + 1
                }
                push(.self = $&storage, .value = sum, .allocator = allocator)!
                col = col + 1
            }
            row = row + 1
        }

        result = ..ok(._rows = left&._rows, ._cols = right&._cols, ._values = ~storage)
    }
)

_math_transpose_dynamic_matrix := #(.t: Type: Scalar, .Provider: Type: Allocator#(Provider)) (
    .self         : &DynamicMatrix#(.t: t),
    .allocator    : $&Provider,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(DynamicMatrix#(.t: t), (..out_of_memory))) {
    assume error_tracer

    count ::= length(&self&._values).count
    storage ::= DynamicArray#(.t: t)(.allocator = allocator, .capacity = count)!

    if count == 0 {
        result = ..ok(._rows = self&._cols, ._cols = self&._rows, ._values = ~storage)
        return
    }

    col :: UIntNative = 0

    while col < self&._cols {
        row :: UIntNative = 0
        while row < self&._rows {
            value ::= unwrap_or_abort(.value = get(.self = self, .row = row, .col = col)).result
            push(.self = $&storage, .value = value, .allocator = allocator)!
            row = row + 1
        }
        col = col + 1
    }

    result = ..ok(._rows = self&._cols, ._cols = self&._rows, ._values = ~storage)
}

DynamicVector := #(.t: Type: Scalar) (._values: DynamicArray#(.t: t))

DynamicVectorInitArgs: Type = #(.t: Type: Scalar, .Provider: Type: Allocator) (
    .values    : ArrayView#(.t: t),
    .allocator : $&Provider
    ,
    .error_tracer : $&Virtual#(ErrorTracer)
)

implement#(.t: Type: Scalar, .Provider: Type: Allocator) Init#(
    DynamicVector#(.t: t), DynamicVectorInitArgs#(t, Provider)
) (
    .Result : Type = Errable#(DynamicVector#(.t: t), (..out_of_memory))

    .init = DynamicVectorInitArgs#(t, Provider) -> (.result: Result) {
        assume error_tracer

        _init_values ::= values
        _init_allocator ::= allocator

        count ::= length(&_init_values).count
        storage ::= DynamicArray#(.t: t)(.allocator = _init_allocator, .capacity = count)!
        i :: UIntNative = 0

        while i < count {
            value ::= unwrap_or_abort(.value = get(.self = &_init_values, .index = i)).result
            push(.self = $&storage, .value = value, .allocator = _init_allocator)!
            i = i + 1
        }

        result = ..ok(._values = ~storage)
    }
)

length := #(.t: Type: Scalar) (.self: &DynamicVector#(.t: t)) -> (.count: UIntNative) {
    count = length(&self&._values).count
}

_math_get_dynamic_vector := #(.t: Type: Scalar) (
    .self: &DynamicVector#(.t: t), .index: UIntNative, .error_tracer: $&Virtual#(ErrorTracer)
) -> (.result: Errable#(t, (..out_of_bounds))) {
    assume error_tracer

    result = get(.self = &self&._values, .index = index)
}

_math_set_dynamic_vector := #(.t: Type: Scalar) (
    .self         : $&DynamicVector#(.t: t),
    .index        : UIntNative,
    .value        : t,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Void, (..out_of_bounds))) {
    assume error_tracer

    pointer ::= get_mutable_reference(.self = $&self&._values, .index = index)!
    pointer&= value

    result = ..ok Void()
}

_math_dot_dynamic_vector := #(.t: Type: Scalar) (
    .left         : &DynamicVector#(.t: t),
    .right        : &DynamicVector#(.t: t),
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(t, (..dimension_mismatch))) {
    assume error_tracer

    count ::= length(left).count

    if count != length(right).count {
        result = ..error(.reason = ..dimension_mismatch)
        return
    }

    sum ::= zeroed#(.t: t)().value
    i :: UIntNative = 0

    while i < count {
        a ::= unwrap_or_abort(.value = get(.self = left, .index = i)).result
        b ::= unwrap_or_abort(.value = get(.self = right, .index = i)).result
        sum = sum + a * b
        i = i + 1
    }

    result = ..ok sum
}

implement#(.t: Type: Scalar) Add#(&DynamicVector#(.t: t), &DynamicVector#(.t: t)) (
    .Result : Type = Errable#(DynamicVector#(.t: t), (..dimension_mismatch, ..out_of_memory))
    .add    = #(.Provider: Type: Allocator) (
        .left         : &DynamicVector#(.t: t),
        .right        : &DynamicVector#(.t: t),
        .allocator    : $&Provider,
        .error_tracer : $&Virtual#(ErrorTracer)
    ) -> (.result: Result) {
        assume error_tracer

        assume allocator

        count ::= length(left).count

        if count != length(right).count {
            result = ..error(.reason = ..dimension_mismatch)
            return
        }

        storage ::= DynamicArray#(.t: t)(.allocator = allocator, .capacity = count)!
        i :: UIntNative = 0

        while i < count {
            a ::= unwrap_or_abort(.value = get(.self = left, .index = i)).result
            b ::= unwrap_or_abort(.value = get(.self = right, .index = i)).result
            push(.self = $&storage, .value = a + b, .allocator = allocator)!
            i = i + 1
        }

        result = ..ok(._values = ~storage)
    }
)

_math_scale_dynamic_vector := #(.t: Type: Scalar, .Provider: Type: Allocator#(Provider)) (
    .self         : &DynamicVector#(.t: t),
    .factor       : t,
    .allocator    : $&Provider,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(DynamicVector#(.t: t), (..out_of_memory))) {
    assume error_tracer

    count ::= length(self).count
    storage ::= DynamicArray#(.t: t)(.allocator = allocator, .capacity = count)!
    i :: UIntNative = 0

    while i < count {
        value ::= unwrap_or_abort(.value = get(.self = self, .index = i)).result
        push(.self = $&storage, .value = value * factor, .allocator = allocator)!
        i = i + 1
    }

    result = ..ok(._values = ~storage)
}
