-- Así con generics

Complex<T: Float> : Type = struct [
  .re : T
  .im : T
]

add (.a: Complex, .b: Complex) -> (out: Complex) := {
  out.re = a.re + b.re
  out.im = a.im + b.im
}

mul (.a: Complex, .b: Complex) -> (out: Complex) := {
  out.re = a.re*b.re - a.im*b.im
  out.im = a.re*b.im + a.im*b.re
}


-- Así con abstracts

Complex :: Abstract = [
	operator +(_, _) :: _
	operator -(_, _) :: _
	operator *(_, _) :: _
	operator /(_, _) :: _
	...
]

Complex8 implements Complex
Complex16 implements Complex
Complex32 implements Complex
Complex64 implements Complex
Complex128 implements Complex
-- El número del nombre corresponde a lo que ocupa cada COMPONENTE del número
Complex defaultsto Complex32

Complex implements Number


-- TODO: Pensar en como hacerlo.
