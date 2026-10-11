-- Example using generics.

Complex#(.t: Type: Float): Type = (
    .re : t
    .im : t
)

add#(.t: Type: Float)(.a: Complex#(.t: t), .b: Complex#(.t: t)) -> (.out: Complex#(.t: t)) := {
    out.re = a.re + b.re
    out.im = a.im + b.im
}

mul#(.t: Type: Float)(.a: Complex#(.t: t), .b: Complex#(.t: t)) -> (.out: Complex#(.t: t)) := {
    out.re = a.re * b.re - a.im * b.im
    out.im = a.re * b.im + a.im * b.re
}

-- Example using abstracts.

Complex: contract = (
    operator + (.left: Self, .right: Self) -> (.result: Self)
    operator - (.left: Self, .right: Self) -> (.result: Self)
    operator * (.left: Self, .right: Self) -> (.result: Self)
    operator / (.left: Self, .right: Self) -> (.result: Self)
    ...
)

Complex8 satisfies Complex
Complex16 satisfies Complex
Complex32 satisfies Complex
Complex64 satisfies Complex
Complex128 satisfies Complex
-- The number in the name is the size of each COMPONENT of the number.
Complex defaultsto Complex32

Complex satisfies Number

-- TODO: Consider how to implement this.
