# Functions

Functions are first class citizen.

All functions are unary.


## Function definition syntax

```
add ( .a: Int, .b: Int ) -> (.o: Int) := {
    o = a + b
}

square (i:Int) -> (o:Int) := {o = i^2}
```

Functions may also be marked with `once` to express that the function is meant
to be consumed at most once from the reachable call graph of the compiled
entrypoint. See [`44_once.md`](./44_once.md).

- All parameters are passed in a single input struct (`in`).
- All results are returned in a single output struct (`out`).


return variables are initialized (to zero) if named.

```
calculate_stats (.l: List#(.t: Float)) -> (.mean: Float, .standard_deviation: Float) := {
	for element in in{
		...
	}
	mean = sum / count
	standard_deviation = sqrt(sum_of_squares / count - mean^2)
}
```

> [!CHECK]
> When are output arguments initialized?
> Do they use their `init`, or are they just the struct that represents them,
> with no fields? Perhaps they wait for their first assignment before calling `init`.


Most extended syntax to add documentation

```
my_function
	---
	Explanation of what the function does
	---
(
	.a: Int  -- Short description of a
	.b: Bool
	---
	Longer description of b
	---
	.verbose: Bool = False  -- Default value
) -> (
	.result_one: Bool
	.result_two: Int
) {
	...
}
```

The empty struct literal is like saying void:

```
my_function () -> () := {
	-- Receives and returns nothing.
}
```

> [!CHECK] Can you ommit things?


## Pipe operator

Calls the function on the right with the arguments returned by the function on
the left. Sometimes currying is needed to make the arguments fit.

```
my_var | my_func
my_var | my_func (_, other_arg)
my_var | my_func (_.a, other_arg, _.b)  -- Multiple piped arguments
```

> [!IDEA]
> If output arguments are named, they could be used instead of `_1`, `_2`, etc.
> Consider how to do this without colliding with variable names.

When passing by reference:

```
my_var | my_func &_
my_var | my_func (&_, second_arg)
```

This provides the convenience of objects.

> [!FIX] If the function operating on an “object” comes from a module, the
> module would need to be mentioned. This is a little tedious.


#### Automatic dereferencing syntax

Inside a function that receives pointers, it is common to want to treat the
pointed-to value as the value itself.

Automatic dereferencing syntax can be used for this:

```rg
funcion_que_lee &Map<String,Int>& := {
	...
}

funcion_que_escribe $&Map<String,Int>& := {
	...
}
```


This lets the function use `datos` directly, as if it had written `datos&`.

Whenever only the value is used and nothing is done with the pointer itself,
the compiler will recommend this syntax. This ensures that when a pointer is
passed to inner functions, `&datos` or `$&datos` is visible and the reference
passing is clear.

> [!TODO] Update the rest of the code to use this syntax.


#### Side effects

If a function has side effects, it requires marking with `$`, and it
propagates.

This allows to understand the effect of a function at a glance, avoiding
unexpected side effects. This is in some way a capability-based programming
style.

It encourages the use of pure functions, which are easier to reason about and
test; and dependency inyection, which allows for more explicit, flexible and
modular code.

For example, accessing a database:

```rg
import db

main system:$&System -> sc:StatusCode := {
	-- Create a database connection.
	db_conn = db.open_database("my_db")

	-- Call a pure function that queries the database.
	user = query_user($&db_conn, 123)
}

query_user (.db_conn: $&DbConnection, .user_id: Int) -> (.user: ?User) := {
	-- Access the database.
	row = db_conn|execute($&_, "SELECT * FROM user WHERE id = ?", user_id)
	if row == null { user = null }
	user = parse_user(row)
}
```

> [!NOTE] This may be a good syntax for naming arguments when needed.
> If no names are provided, use `in` and `out` for concise lambda syntax.


##### Closures

Several forms of closures are possible:

- Uso de variables de un scope exterior.

	- By value: capture the data in the function. No side-effect annotation is
	required.

	- By reference: probably the same.

	- By mutable reference: REQUIRES A SIDE-EFFECT ANNOTATION.

- Reassigning variables from an outer scope. REQUIRES A SIDE-EFFECT ANNOTATION.

```
variable := 4

contador$ () -> () := {
	variable += 1
}

contador$ () -- variable = 5
```

> [!CHECK] Is this how a function with no input arguments should be called?

This makes it clear, with syntax similar to function arguments, whether a
function has side effects.

> [!TODO] Consider whether closures with side effects should be allowed.
> Haskell does not allow them, for example. They may be an anti-pattern and
> could be prohibited to keep the language cleaner; `$` would also mark the
> effectful functions clearly.


##### Capabilities

Capabilities define what a function can do, and they have to be explicitly
passed to the function. All of them are passed to the main function, and can be
passed to other functions as needed.

```
main (system: $&System&) -> (status_code: $&StatusCode&) := {
    -- Use system here to access system capabilities.
    ...
}
```

`System` aggregates references to the process capabilities. The program entry
scope owns the resources, passes the aggregate to `main(.system: System)`, and
cleans them up after `main` returns. Copying System copies these references,
not their resources; safety tracks the dependencies of each copy.

Inside main, select the dependencies needed by ordinary calls:

```rg
main(.system: System) -> (.status_code: Int32 = 0) := {
    assume allocator ::= $&GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume stdout := system.terminal&.stdout_writer
    run()
}
```

The entry wrapper is checked by the same ownership and safety rules as other
functions. System has no owning storage or resource-acquiring constructor.

For capabilities that would otherwise force repetitive argument threading, a
function may declare a reached argument with `reach`. This keeps the
dependency explicit in the function interface while allowing the compiler and
LSP to propagate it through intermediate calls.

Typical examples are:

- `allocator`
- `system`
- `stdout`
- `logger`

```
System : Type = (
  allocator : $& Allocator,
  terminal : $& Terminal,
  args     : $& Arguments,
  env_vars : $& EnvironmentVariables,
  file_sys : $& FileSystem,
)

```

Examples of use:

```rg
main (system: $&System&) -> (status_code: $&StatusCode&) := {
	-- Access the console.
	system.terminal | print ($&_, "Hello, world")

	-- Access command-line arguments.
	arg0 = system.args[0]

	-- Access environment variables.
	env_var = system.env_vars | get (&_, "MY_ENV_VAR")

	-- Access the file system.
	file1 = system.file_sys | open_read (&_, "my_file.txt")
	content = system.file_sys | read_file (&_, "my_file.txt")
	file2 = system.file_sys | open_write (&_, "output.txt")
	file2 | write ($&_, content)

	status_code = ..OK
}
```

Today the stable, actually implemented nucleus of `System` is:

- `allocator`
- `terminal`
- `args`
- `env_vars`
- `file_sys`

Other capabilities may exist experimentally in the runtime shape, but should
not yet be treated as part of the stable everyday model until they gain real
operations and tests.

Capabilities are implemented as abstract types or lightweight capability
structs, depending on the shape that best fits the feature.

When a capability wraps a process-level runtime resource, the low-level handle
should stay explicit in the capability storage instead of being disguised as an
ordinary high-level value. In the current baseline this means, for example:

- `Arguments` keeps the raw argument-vector `address` it receives from the runtime and
  builds borrowed `StringView` values on top of it.
- `File` keeps the raw `stream_address` of the underlying C `FILE*`, while the
  higher-level `Reader`/`Writer` APIs stay separate.
- `Terminal` exposes both the raw stdio files and the higher-level buffered
  wrappers / abstract endpoints.

That keeps the FFI/runtime edge honest without forcing everyday callers to work
directly with those raw addresses.

The current initialization story is intentionally small and explicit:

- `System` starts from process-level runtime state rather than from a hidden VM.
- `allocator` is the C allocator capability.
- `terminal` wraps the preopened stdio streams provided by the host runtime.
- `args` snapshots the process argument count plus the raw argument-vector
  address from the runtime entrypoint.
- `env_vars` and `ffi` are zero-state capability roots whose behavior lives in
  their operations, not in hidden initialization payloads.

That is enough for the current `build` / `test` / `lsp` era of the language
without pretending the runtime capability story is broader than it is today.

```rg
Clock : Abstract = (
    now         (&_)            -> (TimeStamp)
    sleep       (&_, Duration)  -> ()
    sleep_until (&_, TimeStamp) -> ()
)
```

```rg
Rng : Abstract = (
    next_bytes(.self: $&Self, .count: Int) -> (.bytes: Array#(.t: Byte))
    next_int(.self: $&Self, .min: Int, .max: Int) -> (.value: Int)
)
```


> [!IDEA]
> There could be reserved names that automatically add the input to every
> function call up to `main` when used.
> file_sys, terminal, env_vars, args
> This would make it convenient to add a `print`, for example.
> If the program is saved and some of these are unused, they are removed from the input.


##### The case for printing


```rg
import io
import fs


main (system: $&System&) -> (status_code: $&StatusCode&) := {
	-- Create an I/O file.
	stdo = system.terminal.stdout_buffered_writer

	-- Call a pure function that prints.
	do_something_pure(123, log = $&stdo)
}

-- We can use the `stdo` argument to control whether it prints.
do_something_pure(a: Int, $&log: Buffer? = null) -> () := {
	if log { log|write($&_, "Hello, world\n") }
}
```



###### The case for halting the program

Halting is a capability.


### Dispatch

Multiple dispatch, as in Julia.

The functions must be monomorphized at compile time.

This provides behavior similar to object-based static dispatch, but more
flexibly.

Ambiguous specificity is an error, and the compiler detects it.

> [!NOTE]
> Function signatures are part of the callable interface, so every input and
> output field in a function declaration must spell out its type explicitly.
> Defaults may provide fallback values, but they do not infer signature types.

In Go, methods cannot be defined for structs from other packages. That is
frustrating.

#### Multiple dispatch for default implementations

It can be used to provide default implementations for any struct, for example,
providing functionality similar to Rust derive macros.

```rg
to(.self: &Struct, .to: Type = String) -> (.string: String) := {
	string = self.symbol_name + "("
	for field in self.fields
		string += field.name + ": " + field.value + ", "
	string += ")"
}
```

> [!IDEA]
> For a value to be hashable, all its fields must be hashable. If this can be
> checked in a comptime function, the LSP could use that check.
> This could be similar to an interface, except that instead of checking
> whether a value matches a function's input, comptime code would run depending
> on whether the value satisfies the interface.


> [!CHECK]
> Should we consider output types for the dispatch too?
> It can be useful, but it can also make it harder to infer types.
> Compile time could get exponential if not careful.


### Operator overloading

```
operator + (&v1: Vector, &v2: Vector) := Vector {
    return Vector(v1.x + v2.x, v1.y + v2.y)
}
```

```
operator - (&v1: Vector, &v2: Vector) := Vector {
    return Vector(v1.x - v2.x, v1.y - v2.y)
}
```

```
operator - (&v: Vector) := Vector {
    return Vector(-v.x, -v.y)
}
```


### Currying

Currying can be very clean in some cases.

For example, Go's `http.HandleFunc("pattern", function)` requires the function
to take `(r, w)` as arguments. This prevents passing other arguments, such as a
database or templates, which are needed to use pure functions instead of globals.

A convenient currying syntax would help.

```
mux | HandleFunc($&_, "pattern", my_function(_a, _b, database, templates))
```

> [!CHECK] Consider how currying syntax fits with the new function syntax.


### Silently ignoring return values

As in zig, you cannot silently ignore return values. You have to use `_` to ignore them.

```zig
_ = my_function()
```
