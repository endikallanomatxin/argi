Box#(.t: Type): Type = (.value: t)

main() -> () := { value: Box#(4) = (.value = 1) }
