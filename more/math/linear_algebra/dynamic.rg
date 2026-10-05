-- Owners preserve a checked row-major shape; no exported mutable shape fields.
DynamicMatrix#(.t: Type: Scalar): Type = (
    ._rows   : UIntNative,
    ._cols   : UIntNative,
    ._values : DynamicArray#(.t: t)
)

..dimension_mismatch

_extent(
        .rows : UIntNative,
        .cols : UIntNative
    ) -> (
        .result : Errable#(UIntNative, (..dimension_mismatch))
    ) := {
    maximum :: UIntNative = 0
    i :: UIntNative = 0

    while i < size_of(.type = UIntNative) {
        maximum = maximum * 256 + 255
        i = i + 1
    }

    if cols != 0 {
        if rows > maximum / cols {
            result = ..error(.reason = ..dimension_mismatch)
            return
        }
    }

    result = ..ok rows * cols
}

DynamicMatrix init#(
        .t : Type: Scalar
    )(
        .rows      : UIntNative,
        .cols      : UIntNative,
        .values    : ArrayViewRO#(.t: t),
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(DynamicMatrix#(.t: t), (..dimension_mismatch, ..out_of_memory))
    ) := {
    count ::= _extent(.rows = rows, .cols = cols)!

    if count != length(&values).count {
        result = ..error(.reason = ..dimension_mismatch)
        return
    }

    storage ::= DynamicArray#(.t: t)(.allocator = allocator, .capacity = count)!
    i :: UIntNative = 0

    while i < count {
        item ::= unwrap_or_abort(.value = get(.self = &values, .index = i)).result
        push(.self = $&storage, .value = item, .allocator = allocator)!
        i = i + 1
    }

    result = ..ok(._rows = rows, ._cols = cols, ._values = ~storage)
}

shape#(.t: Type: Scalar)(.self: &DynamicMatrix#(.t: t)) -> (.rows: UIntNative, .cols: UIntNative) := {
    rows = self&._rows
    cols = self&._cols
}

get#(
        .t : Type: Scalar
    )(
        .self : &DynamicMatrix#(.t: t),
        .row  : UIntNative,
        .col  : UIntNative
    ) -> (
        .result : Errable#(t, (..out_of_bounds))
    ) := {
    if row >= self&._rows or col >= self&._cols {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    result = get(.self = &self&._values, .index = row * self&._cols + col)
}

set#(
        .t : Type: Scalar
    )(
        .self  : $&DynamicMatrix#(.t: t),
        .row   : UIntNative,
        .col   : UIntNative,
        .value : t
    ) -> (
        .result : Errable#(Void, (..out_of_bounds))
    ) := {
    if row >= self&._rows or col >= self&._cols {
        result = ..error(.reason = ..out_of_bounds)
        return
    }

    pointer ::= get_rw_ref(.self = $&self&._values, .index = row * self&._cols + col)!
    pointer&= value

    result = ..ok Void()
}

add#(
        .t : Type: Scalar
    )(
        .left      : &DynamicMatrix#(.t: t),
        .right     : &DynamicMatrix#(.t: t),
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(DynamicMatrix#(.t: t), (..dimension_mismatch, ..out_of_memory))
    ) := {
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

multiply#(
        .t : Type: Scalar
    )(
        .left      : &DynamicMatrix#(.t: t),
        .right     : &DynamicMatrix#(.t: t),
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(DynamicMatrix#(.t: t), (..dimension_mismatch, ..out_of_memory))
    ) := {
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
                a ::= unwrap_or_abort(.value = get(.self = left, .row = row, .col = k)).result
                b ::= unwrap_or_abort(.value = get(.self = right, .row = k, .col = col)).result
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

transpose#(
        .t : Type: Scalar
    )(
        .self      : &DynamicMatrix#(.t: t),
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(DynamicMatrix#(.t: t), (..out_of_memory))
    ) := {
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

DynamicVector#(.t: Type: Scalar): Type = (._values: DynamicArray#(.t: t))

DynamicVector init#(
        .t : Type: Scalar
    )(
        .values    : ArrayViewRO#(.t: t),
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(DynamicVector#(.t: t), (..out_of_memory))
    ) := {
    count ::= length(&values).count
    storage ::= DynamicArray#(.t: t)(.allocator = allocator, .capacity = count)!
    i :: UIntNative = 0

    while i < count {
        value ::= unwrap_or_abort(.value = get(.self = &values, .index = i)).result
        push(.self = $&storage, .value = value, .allocator = allocator)!
        i = i + 1
    }

    result = ..ok(._values = ~storage)
}

length#(.t: Type: Scalar)(.self: &DynamicVector#(.t: t)) -> (.count: UIntNative) := {
    count = length(&self&._values).count
}

get#(
        .t : Type: Scalar
    )(
        .self  : &DynamicVector#(.t: t),
        .index : UIntNative
    ) -> (
        .result : Errable#(t, (..out_of_bounds))
    ) := {
    result = get(.self = &self&._values, .index = index)
}

set#(
        .t : Type: Scalar
    )(
        .self  : $&DynamicVector#(.t: t),
        .index : UIntNative,
        .value : t
    ) -> (
        .result : Errable#(Void, (..out_of_bounds))
    ) := {
    pointer ::= get_rw_ref(.self = $&self&._values, .index = index)!
    pointer&= value

    result = ..ok Void()
}

dot#(
        .t : Type: Scalar
    )(
        .left  : &DynamicVector#(.t: t),
        .right : &DynamicVector#(.t: t)
    ) -> (
        .result : Errable#(t, (..dimension_mismatch))
    ) := {
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

add#(
        .t : Type: Scalar
    )(
        .left      : &DynamicVector#(.t: t),
        .right     : &DynamicVector#(.t: t),
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(DynamicVector#(.t: t), (..dimension_mismatch, ..out_of_memory))
    ) := {
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

scale#(
        .t : Type: Scalar
    )(
        .self      : &DynamicVector#(.t: t),
        .factor    : t,
        .allocator : $&Allocator
    ) -> (
        .result : Errable#(DynamicVector#(.t: t), (..out_of_memory))
    ) := {
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
