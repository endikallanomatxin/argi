# Module distribution implementation

Model: [Modules](../description/02_modules.md). Directory modules remain usable
without a manifest or programmable build script.

1. Parse distribution metadata and validate nested roots. Separate configuration
   lookup from distribution ownership and project-root imports.
2. Resolve provenance, exact versions and internal paths into an immutable module
   map. Preserve those identities in frontend caches; never collapse origins or
   versions by directory basename. Download complete distributions.
3. Manage exact resolutions in `[lock]` within `argi.toml`. Preserve user content
   outside the marked section; never silently re-resolve locked dependencies.
4. Specify and implement optional `build.rg` task execution.
5. Add publication tooling separately from distribution declarations.

Cover configuration-only manifests, nested/conflicting distribution roots,
multiple versions/origins and locked reproducibility before enabling resolution.
