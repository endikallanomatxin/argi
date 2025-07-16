## Basic types

### Booleans

and, or, not... se escriben como keywords

Literals are:
- `true`
- `false`


### Numbers

```
RealNumber (Abstract)
├── Int (Abstract)
    ├── DynamicInt (default)
    ├── CustomInt(N)
    ├── Int8
    ├── Int16
    ├── Int32
    ├── Int64
    ├── Int128
    ├── UInt8
    ├── UInt16
    ├── UInt32
    ├── UInt64
    └── UInt128
└── Float (Abstract)
    ├── Float8
    ├── Float16
    ├── Float32 (default)
    ├── Float64
    └── Float128
```

Numbers only allow operatiions and comparisons between same types, so, if you want python-like behaviour, use DynamicInt, DynamicFloat, DynamicNumber...

- Underscores can be added to numbers for clarity (`1_000_000`).
- Ints can be written in binary, octal, or hexadecimal formats using the prefixes `0b`, `0o`, and `0x` respectively.
- Floats can be written in a scientific notation.


