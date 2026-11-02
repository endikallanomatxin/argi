# Modules, configuration, and distribution

## Directory modules

Each directory is a module named after that directory. Its `.rg` files share
one namespace. Imports can be transitive; cycles are rejected.

## One abstraction: the module

Everything is a module. There is no separate package abstraction in the
language. A module may contain submodules and import other modules. Local,
official, and external modules use the same import mechanism; their origin
does not change namespace or visibility rules.

Every module may optionally contain `argi.toml`. This declarative file adds
configuration for compilation, dependencies, tools, testing, and distribution.
Its presence does not create a different kind of module or imply that the
module is distributable. A module can be compiled, run, and tested without a
manifest, using an explicit module path where needed.

### Configuration files

| File | Role |
| --- | --- |
| `argi.toml` | Optional declarative module configuration, organized in optional sections. |
| `build.rg` | Optional programmable automation for builds and complex tasks. |

`argi.toml` remains the source of declarative dependency and distribution
metadata; `build.rg` does not replace it. Exact resolved dependency versions
are stored in an automatically managed `[lock]` section of `argi.toml`, not in
a separate file. This section records resolutions rather than introducing
another module identity or a second dependency declaration. A comment marks
the managed section so users can distinguish it from their configuration:

```toml
# Automatically managed by Argi. Do not edit this section manually.
[lock]
```

The dependency manager updates this section while preserving user-authored
configuration and comments elsewhere in the manifest. The concrete lock entry
schema remains to be specified.

### Distribution identity and ownership

A module declares a distributable identity only by including `[distribution]`:

```toml
[distribution]
name = "example"
version = "1.0.0"
description = "An example Argi distribution"
```

A distribution is a unit of delivery and versioning, not a second language
abstraction. Declaring it does not mean the module has been published. Its
root module and all submodules belong to that distribution and share its
version and dependencies. Submodules may have their own module configuration,
but cannot declare independent distributions inside an enclosing distribution
or acquire separate versions or dependency resolutions there.

The dependency manager resolves, downloads, and versions complete
distributions. The compiler works only with modules. A resolved external
module must be identified unambiguously by its provenance, exact distribution
version, and internal module path; a directory basename alone is not its
identity. Two versions or origins must never silently collapse into one module.

> [!IMPLEMENTATION]
> Distribution metadata, nested-distribution validation, dependency resolution,
> downloads, publication, and `[lock]` generation/consumption are not yet
> implemented. External module identities will be integrated with that resolver;
> current local and bundled imports resolve filesystem modules. `build.rg`
> execution is also pending. The rules above define the model these features
> must implement, rather than commands already available today.

## The official library: `core` and `more`

The official library has two parts. `core/` is the small foundation available
to every program; its public names form an implicit prelude. `more/` is the
broader library for collections, codecs, mathematics, and other domains. Its
modules are imported explicitly. Much of `more/` is still under construction.

Installations include `core` and `more` under `lib/argi/`. Bare imports can
therefore resolve without a source checkout. Library development may use a
local `more/` tree in the working directory or its parent before the installed
library.

## Imports and visibility

Names beginning with `_` are private to their module, except that bundled
`core` modules may use each other's private helpers.

A directory whose name starts with `_` may be
imported only from its parent directory or a module below that parent. For
example, `source/math/_detail` is visible to `source/math` and
`source/math/linear`, but not to `source/app` or another tree. The rule applies
to every `_` component in the resolved import path, regardless of whether the
import uses `./`, `../`, or `.../`.

Unqualified lookup uses the current module and public `core`. Other modules
use named imports; standalone `import("...")` is unsupported. Paths resolve as
follows:

| Prefix | Resolution |
| --- | --- |
| `./` | Current module |
| `../` | Parent module |
| `.../` | Project root |
| No prefix | Bundled `more/` library |

Importing a module also exposes its public directory submodules through qualified
access. The parent can have no `.rg` files; it still provides a namespace:

```rg
math := import("math")
-- Matrix belongs to linear_algebra, not directly to math.
Matrix2: Type = math.linear_algebra.Matrix#(.rows = 2, .cols = 2, .t: Int32)
```

This works for nested types, calls, and values, and for local import aliases.
Submodules are discovered on demand from qualified uses; importing a parent
does not recursively compile its unused descendants. Private `_` directories
follow the visibility rule above for both qualified access and explicit imports.
Members are not flattened into the parent's namespace.

Module-qualified calls accept explicit compile-time arguments, such as
`dep.identity#(.t: Int32)(.value = 42)` or `dep.identity#(Int32)(42)`.

Naming an imported type permits selecting its visible Init evidence for construction.
Automatic cleanup first selects the caller's visible Deinit evidence, then looks
in the type's defining module if none is available. Reached arguments still come from
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

## Module configuration and layout

Any directory module with a valid `main` can be built as an executable; its
path has no special meaning. `main` may be declared in any `.rg` file in that
directory. A module's optional `argi.toml` lists the modules it wants to build as
named executable targets:

```toml
[module]
name = "example"

[executables.app]
path = "source/app"

[run]
default = "app"
```

`[module].name` is a descriptive configuration name, not a distribution
identity. `argi init` does not generate `[distribution]` or a version. Legacy
top-level `name` and `version` entries do not declare a distribution either.

> [!IMPLEMENTATION]
> Build/run currently require declared executable targets when the selected
> directory contains a manifest. A configuration-only manifest does not yet
> fall back to that directory's `main`. Enclosing executable selection and
> `.../` project-root lookup currently use manifest boundaries, rather than
> distribution ownership. Nested configuration inheritance and distribution
> boundaries must be separated when distribution support is implemented.

Configured executables default to `build/debug/<name>`; direct module builds use
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

## Dependencies and testing

Dependency declarations belong in `argi.toml`; exact resolved distribution
versions belong in the managed `[lock]` section of `argi.toml`. Submodules within a distribution use its shared
dependencies. The concrete dependency declaration schema and resolver commands
remain pending; there is no implemented `argi add` or `argi remove` command.

Module test selection is independent of distribution identity:

```toml
[test]
modules = ["tests/unit", "tests/integration"]
```

`argi test` runs these modules relative to the manifest in the current directory,
without recursively scanning the tree. `argi test path/to/module` selects one
module explicitly and works without a manifest; use `argi test .` for the current
module. Results include the module path and test name.

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
