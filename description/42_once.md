# Once functions

`once` is a property of a function definition value. The reachable call graph
of the compiled entrypoint may consume that function at most once.

```argi
init_terminal := once () -> () {
    ...
}

main := () -> (.status_code: Int32 = 0) {
    init_terminal()
}
```

The modifier also supports named input types and parameterized definitions:

```argi
acquire := once Args -> (.result: Resource) { ... }
generic := once #(.T: Type) (.value: T) -> (.result: T) { result = ~value }
```

Declarations only bind names. `alias := acquire` preserves the same function
and its once restriction; it creates no additional permission to call it.
The legacy `once acquire := ...` spelling is rejected.

An Init implementation can reuse a once function as its init operation, or
provide an inline once definition. Construction preserves the selected function
identity, so it participates in the same analysis. Contracts do not carry a
separate single-use state.

## Reachability and consumption

The check is relative to the compiled entrypoint, rather than textual across
the repository. A library can define several helpers that call one once function;
compilation fails if an entrypoint reaches more than one such consumption.
Diagnostics identify the repeated function and the paths that consume it.

The analysis is conservative across branches. Calling the same once function
in both arms of an if still counts as duplicate consumption, even though those
arms are mutually exclusive at runtime. This restriction is checked statically;
there is no runtime flag, guard or automatic idempotence.

Each test has its own compiled entrypoint and consumption history. A retained
REPL session extends one history across accepted commands. Rejected preparation
does not consume functions. Reset starts a new history, including calls made by
the ordinary REPL prelude.

## Intended use

Once functions express a unique consumer in the compiled program shape, such
as process-wide capability acquisition or bootstrap steps. They do not implement
an operation that may be called repeatedly but performs work only on its first
runtime invocation.
