Pair #(.t: Type) : Type = (
  .a: t
  .b: t
)

main () -> (.status_code: Int32) := {
  p : Pair#(.t: Int32) = (.a = 20, .b = 22)
  status_code = p.a + p.b
}

