-- Así con generics

Complex#(.t: Type: Float) : Type = (
  .re : t
  .im : t
)

add#(.t: Type: Float) (.a: Complex#(.t: t), .b: Complex#(.t: t)) -> (.out: Complex#(.t: t)) := {
  out.re = a.re + b.re
  out.im = a.im + b.im
}

mul#(.t: Type: Float) (.a: Complex#(.t: t), .b: Complex#(.t: t)) -> (.out: Complex#(.t: t)) := {
  out.re = a.re*b.re - a.im*b.im
  out.im = a.re*b.im + a.im*b.re
}


-- Así con abstracts

Complex : Abstract = (
	operator + (.left: Self, .right: Self) -> (.result: Self)
	operator - (.left: Self, .right: Self) -> (.result: Self)
	operator * (.left: Self, .right: Self) -> (.result: Self)
	operator / (.left: Self, .right: Self) -> (.result: Self)
	...
)

Complex8 implements Complex
Complex16 implements Complex
Complex32 implements Complex
Complex64 implements Complex
Complex128 implements Complex
-- El número del nombre corresponde a lo que ocupa cada COMPONENTE del número
Complex defaultsto Complex32

Complex implements Number


-- TODO: Pensar en como hacerlo.
