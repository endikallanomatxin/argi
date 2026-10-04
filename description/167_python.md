# Python from Argi

`python := import("python")` selects the optional `more/python` module. It embeds
CPython so an Argi program can call existing Python packages. It uses ordinary
C interoperability and the explicit `ForeignFunctionInterface` capability;
Python does not add a language primitive, core dependency, or `System` field.

```rg
python := import("python")
main(.system: System) -> (.status_code: Int32 = 0) := {
    interpreter ::= unwrap_or_abort(.value = python.Python(.ffi = system.ffi)).result
    json ::= unwrap_or_abort(.value = python.import_module(.self = &interpreter, .name = "json")).result
    loads ::= unwrap_or_abort(.value = python.attribute(.self = &json, .name = "loads")).result
    text ::= unwrap_or_abort(.value = python.string(.self = &interpreter, .value = "42")).result
    arguments: [1]&python.Object = (&text)
    number ::= unwrap_or_abort(.value = python.call(.self = &loads, .arguments = view(.array = &arguments))).result
    if unwrap_or_abort(.value = python.to_int64(.self = &number)).result != 42 { abort }
}
```

## Ownership and execution

`Python(.ffi, .program_name = "python3", .home = "")` returns
`Errable<Python, python_initialization_failed>`. A context owns the interpreter
and must remain on its creating thread. One interpreter initialization attempt is allowed
per process. Cleanup finalizes CPython; interpreter restart and subinterpreters
are outside this contract. A pre-existing interpreter cannot be adopted.

`Object` owns one Python reference and borrows its context. It cannot be copied
implicitly: transfer ownership with `~`, or use `clone(.self: &Object)` to acquire
another reference. Normal automatic cleanup releases objects before their
context. Explicit context cleanup invalidates remaining objects; Argi's ordinary
borrow checking rejects subsequent use. Private handles cannot be forged by
consumers and never establish Argi safe references to Python storage.

Python code executes synchronously. Imports, calls, attribute access, collection
operations, and cleanup may execute arbitrary Python code, including extension
modules. Python code retains its normal access to the process and filesystem.
Callbacks into Argi, cross-thread calls, shared buffers, and automatic binding
generation require separate contracts.

## Objects and conversions

Object-producing operations return `Errable<Object, python_error>`:

- `import_module(.self: &Python, .name: StringView)` and
  `attribute(.self: &Object, .name: StringView)`.
- `call(.self: &Object, .arguments: ArrayViewRO<&Object>, .keywords: ?&Object)`.
  Arguments default to empty; keywords default to absent and otherwise must be
  a Python dictionary. Each argument remains borrowed during the call.
- `none`, `boolean(.value: Bool)`, `integer(.value: Int64 or UInt64)`,
  `floating(.value: Float64)`, `string(.value: StringView)`, and
  `bytes(.value: StringView)`, all with `.self: &Python`.
- `list(.self: &Python)`, `dictionary(.self: &Python)`,
  `get_item(.self: &Object, .key: &Object)`, `repr`, and `clone`.

`append(.self: &Object, .value: &Object)` requires a list.
`set_item(.self: &Object, .key: &Object, .value: &Object)` follows Python's
item-assignment protocol. Both return `Errable<Void, python_error>`.
`length(.self: &Object)` returns `Errable<UIntNative, python_error>` using
Python's length protocol. These calls can mutate Python objects through shared
Argi references; Python's own object model governs that mutation.

`to_int64` and `to_uint64` require Python integers, exclude booleans, and check
range. `to_float64` requires a Python float; `to_bool` requires a Python boolean.
No truthiness or automatic integer/float conversion is performed. `is_none`
checks identity with `None`. Conversion failures return `python_error`.
Extension-specific scalar types should be converted through their Python APIs
first, such as NumPy's `tolist` or `item`.

`to_string(.self: &Object, .allocator: $&Allocator)` requires Python `str` and
copies UTF-8 into an owning Argi `String`. `to_bytes` requires Python `bytes`
and copies arbitrary bytes into a `String` without decoding. Both return
`Errable<String, python_error | out_of_memory>`. Embedded NUL bytes are
preserved in values; module names, attribute names, and interpreter paths reject
them. `string` decodes its input as strict UTF-8. No result borrows Python buffers.

## Errors and environment

A failed operation captures the Python exception class, message, and available
traceback. `error_text(.self: &Python, .allocator: $&Allocator)` returns an owning
copy of the most recent failure text, or empty text before any failure.
Successful operations and object cleanup preserve that text; a later failure
replaces it. Exception formatting falls back to a simple exception description
if traceback formatting fails. Errors are returned without printing the captured
exception to stderr; Python code itself can still write output.

Initialization failures return their reason; `initialization_error(.ffi)`
captures their details without needing a Python context.
Finalization cannot return an error through automatic cleanup.

`program_name` selects the Python executable used to discover the runtime and
its environment, including a virtual environment. `home`, when nonempty, sets
an explicit Python installation root; leave it empty for a virtual environment.
Normal Python environment and site configuration apply. Signal handlers remain
owned by the parent application and an implicit current-directory import entry
is not added. Package installation and discovery belong to that Python
environment, independently of Argi module lookup.

The adapter requires CPython 3.12 or newer with the standard GIL-enabled build,
matching development headers, and its embedding library. Build and link it
explicitly as described in [the module instructions](../more/python/README.md).

CPython references: [initialization configuration](https://docs.python.org/3/c-api/init_config.html)
and [reference ownership](https://docs.python.org/3/c-api/refcounting.html).

## Argi values and arguments

`to_object(.self: &Python, .value)` is an ordinary overload family for signed
and unsigned integer primitives, Bool, Float32/Float64, StringView, borrowed
String, and borrowed Object (which acquires a new reference). Integer widening
is explicit inside the module. Float16 is not supported by this boundary.
Read-only and mutable views, fixed arrays, and DynamicArray owners convert into
Python lists. Collection elements are copied or converted; Python results retain
no borrow of the input collection. Nested collections convert recursively.

`Argument` is an implicitly copyable choice for heterogeneous inputs, with
`none`, `boolean Bool`, `integer Int64`, `unsigned UInt64`, `floating Float64`,
`text StringView`, and `object &Object` alternatives. It owns no Python reference;
conversion acquires one. `positional_arguments(.self, .values: ArrayViewRO<T>)`
converts a homogeneous view or an Argument view into an owning Python tuple.
Pass that tuple as `.arguments: &Object` to `call`.

`keyword_arguments` accepts a view of `Keyword(.name, .value: &Object)` or
`NamedArgument(.name, .value: Argument)` records and creates an owning Python
dictionary. Repeated names follow normal dictionary assignment: the last wins.
These helpers propagate conversion errors and clean up already-created values.

## Methods, attributes, and iteration

`call_method(.self: &Object, .name: StringView, .arguments, .keywords)` obtains
an attribute, calls it, and releases the temporary callable. Its arguments and
errors follow `call`, including prepared tuple arguments. Method lookup occurs
in Python during execution; Argi dispatch selects an ordinary library function.

`set_attribute(.self: &Object, .name: StringView, .value: &Object)` returns
`Errable<Void, python_error>` using Python's attribute assignment protocol.
`tuple(.self: &Python, .values: ArrayViewRO<&Object>)` creates an owning tuple,
with an empty default value view. Python retains its elements independently of
the Argi view.

`iterate(.self: &Object)` returns an owning `PythonIterator` in an Errable.
`next(.self: $&PythonIterator)` returns `Errable<Nullable<Object>, python_error>`:
an owned item, successful exhaustion (`none`), or a captured exception. It does
not implement core's Iterator abstract, whose next operation is infallible.
The iterator keeps its Python source alive and borrows only its interpreter.
An exhausted iterator may be queried again; exhaustion does not replace the
most recent exception text.

## Retaining individual failures

`snapshot_error(.self: &Python)` returns an owning `Exception` containing
immutable native copies of the last failure's type name, message, and traceback.
Take the snapshot before executing another operation that might fail. A snapshot
survives subsequent failures and interpreter finalization; it retains the
ordinary FFI capability, with no borrowed Python objects or buffers.

`exception_type`, `exception_message`, and `exception_traceback` accept
`.self: &Exception` and `.allocator: $&Allocator` and return owning Strings in
an `Errable<String, out_of_memory>`. `clone(.self: &Exception)` acquires another
snapshot reference. Exceptions are not implicitly copyable and clean up normally.
Native allocation exhaustion uses an immutable MemoryError fallback rather than
silently retaining details from an earlier failure.

`capture(.self: &Python, .value: Errable<T, python_error>)` returns
`Outcome<T>`, an ordinary module-defined choice of `ok T` or `error Exception`.
Wrap an operation immediately, for example:

```rg
outcome ::= python.capture(.self = &interpreter,
    .value = python.import_module(.self = &interpreter, .name = "package")).result
match outcome {
    ..ok ~ module {
        -- Use the imported module here.
    }
    ..error ~ exception {
        -- Retain or inspect this particular failure.
    }
}
```

Passing an older Errable after running another failing Python operation captures
the newer context error; `capture` does not recover discarded history. Existing
operations continue to return core Errable, so ordinary propagation stays intact.

`initialization_error(.ffi: $&ForeignFunctionInterface)` similarly snapshots the
latest failed initialization. Its message covers invalid paths/names, duplicate
initialization, and CPython configuration failures, including the PyStatus error
message. Before any failure, snapshot fields are empty.

## Native preparation

The optional `more/python/build.py` helper discovers native development headers
and the shared embedding library using the Python installation that runs it.
It prepares a cached object and passes ordinary native file dependencies to
Argi, or prints `[[native]]` manifest entries. Neither module imports nor the
compiler perform implicit Python discovery. An adapter prepared this way uses
the helper's Python executable as its default program name, including a virtual
environment; explicit non-default program names continue to override it.

## Numeric buffers and NumPy

`numeric_buffer(.self: &Python, .values: ArrayViewRO<T> or ArrayView<T>)` copies
initialized numeric elements into a Python-owned bytearray in one operation.
It supports Int8/16/32/64, UInt8/16/32/64/Native, and Float32/64. Native byte order
and representation are preserved. Empty inputs need no element address;
byte-count overflow is rejected before reading memory.

`numeric_array(.self, .values)` imports NumPy and calls `frombuffer` with the
matching native dtype. The array keeps the copied Python bytearray alive and is
writable. It has no dependency on the Argi input's lifetime. NumPy is an optional
Python package, with no NumPy headers or compiler hooks required.

`copy_numeric(.self: &Object, .destination: ArrayView<T>)` copies a Python buffer
into an already-initialized writable Argi view and returns the copied element
count in an Errable. It requires a one-dimensional scalar numeric buffer with
matching signedness/type, width, and native byte order. Read-only Python buffers
are accepted; strided and reversed buffers copy in logical element order.
Insufficient capacity, incompatible formats, nonnative byte order, indirect
buffers, and invalid extents fail before any destination slot is changed.
Slots beyond the copied prefix remain unchanged. No implicit numeric conversion,
flattening, byte swapping, or safe-reference construction occurs.

These operations use the [CPython buffer protocol](https://docs.python.org/3/c-api/buffer.html).
NumPy arrays retain their copied storage through
[`frombuffer`](https://numpy.org/doc/stable/reference/generated/numpy.frombuffer.html).

### Sharing Argi storage

Borrowed buffers without copying require an additional foreign-lifetime design.
Python can retain an exporter in globals, callbacks, or another object's state
beyond the lifetime of an Argi handle. A lexical borrow on that handle alone
cannot describe those hidden references. This API therefore keeps all exported
storage owned by Python and imports data into existing Argi owners through
checked copies. Transferring ownership of an allocation or safely sharing an
owner remains a separate design decision.
