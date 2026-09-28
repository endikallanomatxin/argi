# Syntax overview

## Design priorities

The core goals are:

- explicit data flow
- visible side effects
- function composition over object-like syntax
- static dispatch by default
- little semantic magic

When in doubt between a shorter syntax and a more predictable one, prefer the
more predictable one.

## Comments

```
-- One line comments

---
Multiline comments for lengthier explanations
**They allow for markdown syntax**.
---

--*
Nestable comments?
*--

--- Doc comments, like zig
```

Removing multiline comments might make it possible to tokenize everything in
parallel.

## Variable and constant declaration

```
PI          :  Float = 3.141592653  -- Declares a constant
my_variable :: Int   = 42           -- Declares a variable
```

The declaration syntax has two delimeters:

- First, the type annotation delimeter. There are two options:
	- `:` for constants
	- `::` for variables
	When type is omitted, it is inferred from the value.

- Second, the value assignment delimeter. Always ` = `.


On constant structs: When a struct is constant, you are not allowed to:
- Reassign its name
- Reassign its fields
- Create mutable pointers to it
That is enough, because any modification would require a mutable pointer to the
struct.

## Pointers

To get a reference to a variable (as in C, Go, Rust, and others):

```
p = &x
```

To dereference a pointer:

```
x = p&
```

Its type is:

```
p: &Int
```

- It cannot be null.
(To allow null, use a nullable: `?&Int`. See below for more information.)

- Pointer arithmetic is not allowed.
To perform it, convert the pointer to a numeric type, do the arithmetic, then
convert it back to a pointer. This is inconvenient enough to prevent accidental
use and requires an explicit step that could fail.

The canonical numeric type for this is `UIntNative`.


### Read-only vs read-write pointers

There are two types of pointers:
- Read-only pointers: `&T`
- Read-write pointers: `$&T` ($ is for side effects)

> [!TODO] Can a `$&` pointer be passed to a function expecting `&`?
> Is an explicit cast required?


## Code blocks

Everything between `{ }` is considered a code block.

Every code block has its own scope.

This is also used for loops and conditional, so locally declared variables are not accessible outside the block.
This forces the good practice of declaring variables before loops and conditionals, instead of inside them.

> [!CHECK]
> Consider preventing code blocks from capturing anything from outside, as in Jai.
> Also consider convenient syntax for invoking a block like an anonymous
> function. This is even more hygienic, but the syntax should remain simple.

> [!NOTE]
> In Go, writing `v1, v2 := ...` inside a block declares all variables, not
> only the undeclared ones. A variable that already exists is shadowed.
> Our language should avoid this: if a variable exists outside the block, it
> should not be redeclared when several are declared together, only when one is.


## Functions

Functions are declared similar to variables or constants.

They just contain a couple of structs after the name (input and output), separated by an arrow:

```
add (.a: Int, .b: Int) -> (.c: Int) := {
    c = a + b
}

divmod (.n:Int, .d:Int) -> (.quot:Int, .rem:Int) := {
    quot = n / d
    rem  = n % d
}
```

When calling functions:

- you can omit the names of the fields when you specify all of them in the correct order.
- output structs with a single field are automatically unpacked (to avoid unnecessary verbosity).

> [!CHECK]
> Consider avoiding automatic unpacking and filling in defaults at the call
> site to make the code forward-compatible.


```
result = add(1, 2) + add(3, 4)
```

When a function has multiple fields in the output struct, you get the struct.

```
-- Without unpacking:
r = divmod(7, 3)

-- To extract only one field:
quot, _ = divmod(7, 3)
-- or
quot = divmod(7, 3).quot

-- To extract both:
quot, rem = divmod(7, 3)
```

> [!NOTE] How do we distinguish a struct literal from a list literal?
> It is a collection literal that can be _interpreted_ as a list, struct,
> map, or choice literal.


Anonymous functions can be defined like here:

```
some_function_that_needs_another_function(
	(.a: Int, .b: Int) -> (.c: Int) := { c = a + b },
	"Some other argument"
)
```


### Pipe operator

The pipe operator calls the right hand side function, substituting the _ symbol
with the full left hand side expression, if it is a function it contains the
return struct without unpacking.

```
my_var | my_func (_, other_arg)         -- Single piped argument
my_var | my_func (_.a, other_arg, _.b)  -- Multiple piped arguments
result | is(_, ..error)                -- Positional arguments also work with builtins
```

Values can be passed by reference without creating intermediate variables.

```
my_var | my_func (&_, second_arg)
```


## Initialization of types

All types have two methods:
- `init` to create an instance of the type.
- `deinit` to destroy the instance of the type.

### Init

When you delcare a new instance:

```
my_thing := MyType("something", 12, true)
```

> [!TODO]
> Think about syntactic sugar to allow:
> ```
> my_list := (1, 2, 3, 4)
> ```
> which should be:
> ```
> my_list := List#(.t: Int32)(1, 2, 3, 4)
> ```

The init function must be declared like this:

```
init (.empty_struct_pointer: $&MyType, arg1: String, arg2: Int, arg3: Bool) -> (.result: MyType) := {
    ...
}
```

If init function is defined it is called. If it doesn't, it creates an empty struct, if possible.

When init is used, the first argument is the mutable pointer to the declared but uninitialized struct.

So:

```
my_thing := MyType("something", 12, true)
```

is really:

```
my_thing : MyType
init ($&my_thing, "something", 12, true)
```

> [!NOTE] init() is the only function allowed to receive uninitialized arguments.
>
> The first parameter of `init` can be a pointer to memory allocated for that
> type but not yet initialized.
> 
> Static checks inside `init`:
> - Write-only access to `out`: fields cannot be read before they are written
>   (ideally, never read `out`).
> - Definite initialization: every field must be written on every successful path.
> - No escape or aliasing: the pointer cannot escape (do not store it globally,
>   capture it in closures, or pass it to threads).


If wanted you can return an empty errable:

```
..init_failed
init(out: $&MyType, ...) -> Errable#(.t: Void, .reasons: (..init_failed))
```

### Deinit

On scope exit, `deinit` is automatically called for all types that are not in the result struct.
That way, everything behaves as if it were a stack variable.

Passing a named value to an argument declared by value performs an implicit
copy only when its type implements `ImplicitlyCopyable`. Other types require
explicit `copy(&value)` or explicit ownership transfer with `~value`.

> [!NOTE]
> On error or early-return paths, ensure the value remains uninitialized
> (`deinit` will not be called), or that partial initialization is cleaned up
> before returning.
> - `deinit` is called only on initialized objects.
> - If `init` fails (returns an error), `deinit` is not called on that slot.

> [!NOTE] To use the stack, `init` functions must be inlined.
> If the object should be on the stack, `alloca` cannot be called inside a
> function.
> For example, if `Array` were part of the standard library, it would need
> this signature:
> ```
> init#(.t: Type, .n: UIntNative)(.a: &Array#(.t), .source: ListLiteral#(.t)) -> () #inline { ... }
> ```

> [!IDEA]
> Using `init` for casting could work well because it will likely be inlined
> when possible.
> This could be done by overloading the `init` function.
>
> `init(out: $&TargetType, in: SourceType) -> ()`
> It would be used like this:
> `new = TargetType(source_value)`

> [!FIX]
> Calls to `init` functions use the same name as the type, so the `init`
> function cannot be referenced by name. It is unclear whether this is a problem.

> [!CHECK]
> Should the variable produced by initialization be part of the declaration's
> input or output?


## Generics

- Monomorphized at compile time.

- Do not have multiple dispatch.

- Use structs for their arguments.

```
MyGenericType#(.t: Type) : Type = (
	.data : List#(.t: t)
)
```

> [!IDEA] Structural indexing
> Explore using `.` for structural access, including native array indexing:
> `value.field`, `array.i` or even `array.3`.
>
> DynamicArrays, Maps and other library collections can keep explicit
> `get`/`set` abstractions and polymorphism through `Abstract`.
