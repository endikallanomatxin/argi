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

Complex canbe [Complex8, Complex16, Complex32, Complex64, Complex128]
-- El número del nombre corresponde a lo que ocupa cada COMPONENTE del número
Complex defaultsto Complex32

Number canbe Complex


-- TODO: Pensar en como hacerlo.
