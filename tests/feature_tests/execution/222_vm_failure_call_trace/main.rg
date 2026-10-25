fail() -> () := { abort }

middle() -> () := { fail() }

main() -> () := { middle() }
