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

**Planned module privacy:** a directory whose name starts with `_` may be
imported only from its parent directory or a module below that parent. For
example, `source/math/_detail` is visible to `source/math` and
`source/math/linear`, but not to `source/app` or another tree. The rule applies
to every `_` component in the resolved import path, regardless of whether the
import uses `./`, `../`, or `.../`. This module-level rule is not implemented
yet; the current `_` rule protects declarations only.

Unqualified lookup uses the current module and public `core`. Other modules
use named imports; standalone `#import("...")` is unsupported. Paths resolve as
follows:

| Prefix | Resolution |
| --- | --- |
| `./` | Current module |
| `../` | Parent module |
| `.../` | Project root |
| No prefix | Bundled `more/` library |

Import paths must resolve at compile time. The current compiler accepts only
literal paths; computed compile-time paths are not implemented yet.

For example:

```rg
json := #import("codecs/serialization/json")
sibling := #import("./sibling")
parent_dep := #import("../shared")
root_dep := #import(".../app/shared")
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

`build/debug/` is the current package output. `_detail` illustrates the
planned privacy rule; `dist/` remains a distribution idea. No special source
subtree is required.

## Package dependencies

Planned commands:

```sh
argi add <package>
argi remove <package>
```

Dependencies would use `argi.toml` plus a lockfile and a shared global package
store, without per-project virtual environments. These commands and dependency
resolution are not implemented yet.

## C interoperability

Planned named C header import:

```rg
some_c_lib := #c_import("c_module.h")
```

It would map C signatures and structs to Argi calls with named arguments.
Some `more` modules may need native libraries (for example BLAS/LAPACK,
OpenSSL, zlib, or FFmpeg). Builds should diagnose missing libraries; releases
may bundle them per target. `#c_import` and its ABI and linking rules are not
implemented yet.
