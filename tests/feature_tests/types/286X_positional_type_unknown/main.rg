Box#(.t: Type): Type = (.value: t)

main() -> () := { value: Box#(.other: Int32) = (.value = 1) }
