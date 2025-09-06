-- Multiple generic parameters (struct types)

Pair2 #(.a: Type, .b: Type) : Type = (
  .x: a,
  .y: b
)

main () -> (.status_code: Int32) := {
  p : Pair2#(.a: Int32, .b: Char) = (.a = 20, .b = 'X')
  status_code = p.x
}

