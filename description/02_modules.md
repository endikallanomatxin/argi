# Modules and project layout

## Directory modules

Each directory is a module named after that directory. Its `.rg` files share
one namespace. Imports can be transitive; cycles are rejected.

## The official library: `core` and `more`

The official library has two parts. `core/` is the small foundation available
to every program; its public names form an implicit prelude. `more/` is the
broader library for collections, codecs, mathematics, and other domains. Its
modules are imported explicitly. Much of `more/` is still under construction.

## Imports and visibility

Names beginning with `_` are private to their module, except that bundled
`core` modules may use each other's private helpers.

A directory whose name starts with `_` may be
imported only from its parent directory or a module below that parent. For
example, `source/math/_detail` is visible to `source/math` and
`source/math/linear`, but not to `source/app` or another tree. The rule applies
to every `_` component in the resolved import path, regardless of whether the
import uses `./`, `../`, or `.../`.

> [!IMPLEMENTATION]
> Directory privacy is not enforced yet. The current `_` rule protects
> declarations only.

Unqualified lookup uses the current module and public `core`. Other modules
use named imports; standalone `import("...")` is unsupported. Paths resolve as
follows:

| Prefix | Resolution |
| --- | --- |
| `./` | Current module |
| `../` | Parent module |
| `.../` | Project root |
| No prefix | Bundled `more/` library |

Module-qualified calls accept explicit compile-time arguments, such as
`dep.identity#(.t: Int32)(.value = 42)` or `dep.identity#(Int32)(42)`.

Naming an imported type exposes its public `init` overloads for construction.
Automatic cleanup first uses the caller's visible `deinit` overloads, then the
type's defining module if no match exists. Reached arguments still come from
the caller's lexical context. These lifecycle lookups do not expose unrelated
functions from the imported module to unqualified calls.

Import paths must resolve at compile time. Imports in discarded target
`#if` branches are not discovered or resolved; see
[compile-time computation](50_comptime.md#compilation-target).

> [!IMPLEMENTATION]
> The compiler currently accepts only literal import paths.

For example:

```rg
json := import("codecs/serialization/json")
sibling := import("./sibling")
parent_dep := import("../shared")
root_dep := import(".../app/shared")
```

## Package layout

Any directory module with a valid `main` can be built as an executable; its
path has no special meaning. `main` may be declared in any `.rg` file in that
directory. A package's `argi.toml` lists the modules it wants to build as
named executable targets:

```toml
name = "example"

[executables.app]
path = "source/app"

[run]
default = "app"
```

Package executables default to `build/debug/<name>`; direct module builds use
`build/output`. `main.rg` is only a convenient filename. `argi init app`
scaffolds `source/app/main.rg`; `argi init --lib <name>` scaffolds a library
without executable targets.

One possible layout using that rule is:

```text
project/
├── argi.toml
├── source/
│   ├── app/main.rg
│   └── math/
│       ├── vector.rg
│       ├── linear/main.rg
│       └── _detail/helper.rg
└── build/
    ├── debug/app
    └── dist/<target>/
```

`_detail` illustrates directory privacy. No special source subtree is required.

> [!IDEA]
> `dist/<target>/` could hold distribution artifacts.

## Package dependencies

Package management commands:

```sh
argi add <package>
argi remove <package>
```

Dependencies use `argi.toml` plus a lockfile and a shared global package
store, without per-project virtual environments.

> [!IMPLEMENTATION]
> `argi add`, `argi remove`, and dependency resolution are not implemented yet.

## C interoperability

Named C header import:

```rg
some_c_lib := #c_import("c_module.h")
```

It produces the typed declarations described in
[C interoperability](20_c.md), including C signatures and record layouts.
Foreign calls require the `ffi` capability; importing a header does not grant it
or select a library to link.
Some `more` modules may need native libraries (for example BLAS/LAPACK,
OpenSSL, zlib, or FFmpeg). Builds should diagnose missing libraries; releases
may bundle them per target.

> [!IMPLEMENTATION]
> `#c_import` and its ABI and linking rules are not implemented yet.
