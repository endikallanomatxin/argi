## Conditionals

#### If

```
if a == 2 {
	...
} else if a == 3 {
	...
} else {
	...
}
```

#### Match

From Odin: each case has its own scope, with an implicit `break` by default.
Use `fallthrough` or something similar when execution should continue.

```
match x (

	a {
		...
	}

	b {
		...
	}

	...
)
```

> [!IDEA]
> Since we removed `()` to represent functions, we could use them to improve
> the syntax if needed.

I think Rust handles this very well.
Gleam does too.

> [!QUESTION]
>
> In JAI, a switch looks something like this:
> 
> ```
> if bar == {
>     case 1 {
> 		...
> 	}
>     case 2 {
> 		...
> 	}
>     case 3 {
> 		...
> 	}
> }
> ```
> 
> This is like multiplexing `==`. It seems like a very good idea, even more
> powerful than `match`.
> 
> Think this through.

Pattern bindings in `match` should follow the same general access mode model:

```rg
match value {
    ..some payload {
    }

    ..some & payload {
    }

    ..some $& payload {
    }

    ..some ~ payload {
    }

    ..some _ {
    }
}
```

Unified rule:

- `name` binds by value.
- `& name` binds a read-only reference.
- `$& name` binds a mutable reference.
- `~ name` binds by move.
- `_` ignores the value.


## Loops

For

```plaintext
for element in list {
    ...
}

for element, index in list|enumerate {
	...
}

for i in Range(.start = 1, .end = 10) {
    ...
}
```

While

```plaintext
while eps < e-5 {
    ...
}
```

Forever:

```plaintext
loop
    ...
```


### List comprehensions

I do not like them, but they are convenient for small tasks and do not seem
especially prone to misuse. It is fine to implement them.

```
(i*2 for i in Range(.start = 1, .end = 10))
```

Or perhaps the other way around:
- It is immediately clear that this is a list comprehension.
- It is cleaner across multiple lines.

```
evens = (for i in Range(.start = 1, .end = 10) {yield i*2})

evens = (for i in Range(.start = 1, .end = 10); i*2)
```

>[!QUESTION] Reconsider the syntax.

### Iterators

`Iterator` types manage how collections are traversed or processed. They are
defined separately to keep them independent from the collection data itself.

`for` must consume an `Iterable`, not an `Iterator` directly. The iterable
exposes `to_iterator`, and the iterator holds the mutable traversal state.

This can be expressed with `Abstract`:

```
Iterable#(.t: Type) : Abstract = (
    to_iterator(.value: &Self) -> (.iterator: Iterator#(.t: t))
)

ROPointerIterable#(.t: Type) : Abstract = (
    to_ro_pointer_iterator(.value: &Self) -> (.iterator: Iterator#(.t: &t))
)

RWPointerIterable#(.t: Type) : Abstract = (
    to_rw_pointer_iterator(.value: $&Self) -> (.iterator: Iterator#(.t: $&t))
)

Iterator#(.t: Type) : Abstract = (
    has_next(.self: &Self) -> (.ok: Bool)
    next(.self: $&Self) -> (.value: t)
)
```

The design keeps a single `Iterator` abstract. The iteration mode changes the
`Iterable` abstract that the collection implements, not the iterator interface.

This gives the following model:

- `Iterable#(.t: T)` for `for item in value`
- `ROPointerIterable#(.t: T)` for `for & item in value`
- `RWPointerIterable#(.t: T)` for `for $& item in value`

Each constructs an `Iterator`, but with a different element type:

- `Iterator#(.t: T)` for iteration by value
- `Iterator#(.t: &T)` for borrowed read-only iteration
- `Iterator#(.t: $&T)` for borrowed mutable iteration

Useful conceptual note: Rust still has a single `for`, but the type of the
expression passed to it determines the iteration mode.

```
for x in v      -- consumes the collection
for x in &v     -- iterates by immutable reference
for x in &mut v -- iterates by mutable reference
```

This comes from different iterator conversions for:

- `Vec<T>`
- `&Vec<T>`
- `&mut Vec<T>`

The useful idea for Argi is to keep the same principle: `for` consumes an
`Iterable`, and the exact type of the value passed to it should determine
whether iteration is by value, immutable reference, or mutable reference.

Future direction within the same model:

```rg
for item in arr {
}

for & item in arr {
}

for $& item in arr {
}

for ~ item in arr {
}
```

This should make `for` behave like the iteration equivalent of `place`,
`&place`, `$&place`, and `~place`.

Transfer iteration has the form:

```rg
for ~ item in value {
}
```

> [!QUESTION]
> Define how transfer iteration consumes collections and iterators.

> [!IMPLEMENTATION]
> The compiler currently supports `for item`, `for & item`, and `for $& item`.
> Transfer iteration is not supported yet.

Functions such as `map()` and `filter()` could also have versions that consume
iterators (for lazy evaluation) or lists.
_(Consider how this could support vectorizing functions: use a vector version
when the called function has one, otherwise process each element.)_


To make your type iterable:

```
MyType : Type = struct (
    .data: List#(.t: Int)
)

MyTypeIterator : Type = (
    .data: &MyType
    .index: UIntNative
)

MyType implements Iterable#(.t: Int)
MyType implements ROPointerIterable#(.t: Int)
MyTypeIterator implements Iterator#(.t: Int)
MyTypeROIterator implements Iterator#(.t: &Int)

to_iterator(.value: &MyType) -> (.iterator: MyTypeIterator) := {
    iterator = (
        .data = value,
        .index = 0,
    )
}

has_next(.self: &MyTypeIterator) -> (.ok: Bool) := {
    ok = self&.index < length(.value = self&.data&.data)
}

next(.self: $&MyTypeIterator) -> (.value: Int) := {
    current_index :: UIntNative = self&.index
    value = self&.data&.data[current_index]
    self& = (
        .data = self&.data,
        .index = current_index + 1,
    )
}

to_ro_pointer_iterator(.value: &MyType) -> (.iterator: MyTypeROIterator) := {
    iterator = (
        .data = value,
        .index = 0,
    )
}

next(.self: $&MyTypeROIterator) -> (.value: &Int) := {
    -- Returns a reference to the current element.
}
```


```
for element in my_collection {
    print(element)
}

-- This could be written as:

it ::= to_iterator(.value = &my_collection)
while has_next(.self = &it) {
    element := next(.self = $&it)
    print(element)
}
```

`for` must accept the appropriate `Iterable`:

- `for item in x` requires `Iterable`.
- `for & item in x` requires `ROPointerIterable`.
- `for $& item in x` requires `RWPointerIterable`.

Ideas:
- Concatenate iterators with commas: `Range(.start = 1, .end = 5), Range(.start = 80, .end = 92)`.
- In Julia, the dot after `sin` broadcasts the trigonometric function to each element of `x`.
