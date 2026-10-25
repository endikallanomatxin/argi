# Unified module and distribution model

The normative model is [Modules](../description/02_modules.md). There is one
language abstraction: a directory module. Distribution is optional identity
and delivery metadata, not another kind of namespace.

## Remaining implementation

1. Parse and validate distribution metadata independently of module/tool settings.
   Reject nested distribution declarations; retain one version and dependency
   resolution for every submodule in a distribution.
2. Separate configuration lookup from distribution ownership and project-root
   imports. A nested configuration file must not create another distribution.
   Allow configuration-only manifests to retain ordinary direct-module builds.
3. Define dependency declarations, provenance, exact versions, and internal paths.
   Resolve/download complete distributions and feed an immutable resolution map
   to the compiler. Keep origin/version/path in module and frontend-cache identities.
4. Specify and implement the automatically managed `[lock]` section in `argi.toml`,
   including validation of exact resolutions and reproducibility. Mark it with a
   comment, preserve user-authored configuration and comments outside it, and do
   not create a separate lockfile or silently re-resolve locked dependencies.
5. Specify optional `build.rg` task execution separately from declarative metadata.
   Keep ordinary modules usable without it or any manifest.
6. Add publication tooling separately: declaring a distribution never publishes it.

Tokenizing and language syntax need no changes for the formalization. Resolution,
module collection, frontend/cache identities, CLI configuration, and tooling are
involved in the remaining implementation. Codegen continues to consume resolved
modules. Add positive and negative fixtures for nested configurations, conflicting
distribution roots, and multiple versions/origins before enabling resolution.
