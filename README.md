<p align="center">
  <img src="docs/src/assets/logo-dark.svg" alt="Workbench.jl" width="400">
</p>

<p align="center">
  <a href="https://mthelm85.github.io/Workbench.jl/stable/"><img src="https://img.shields.io/badge/docs-stable-blue.svg" alt="Stable"></a>
  <a href="https://mthelm85.github.io/Workbench.jl/dev/"><img src="https://img.shields.io/badge/docs-dev-blue.svg" alt="Dev"></a>
  <a href="https://github.com/mthelm85/Workbench.jl/actions/workflows/CI.yml?query=branch%3Amaster"><img src="https://github.com/mthelm85/Workbench.jl/actions/workflows/CI.yml/badge.svg?branch=master" alt="Build Status"></a>
  <a href="https://github.com/JuliaTesting/Aqua.jl"><img src="https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg" alt="Aqua"></a>
</p>

Workbench provides a **development workspace manager** for Julia packages. It scaffolds and manages sub-projects (`test/`, `docs/`, `benchmark/`, `dev/`, and custom task directories) as [workspace](https://pkgdocs.julialang.org/v1/toml-files/#Project-and-Manifest) members that share a single `Manifest.toml` with your package.

## Why

Julia packages typically need several auxiliary environments — tests, docs, benchmarks, a dev environment for interactive tooling — each with their own dependencies. Managing these by hand means writing `Project.toml` boilerplate, wiring `[sources]` back to the parent package, and manually stacking `LOAD_PATH` for dev tools. Julia 1.12's workspace mechanism provides the infrastructure for this, but the developer experience is entirely manual.

Workbench is the porcelain layer. It automates scaffolding, dependency management, task execution, and dev-tool activation on top of Julia's native workspaces, so every sub-project resolves against one shared `Manifest.toml`:

```
              root Project.toml
                    │
              Manifest.toml  (shared)
                    │
        ┌───────────┼───────────┐
        │           │           │
      test/       docs/     benchmark/
    Project.toml  ...         ...
        │           │           │
        └───────────┴───────────┘
              shared resolution
```

## Installation

Install Workbench in your **global environment** — it is a developer tool, not a package dependency:

```julia
julia> using Pkg; Pkg.add(url="https://github.com/mthelm85/Workbench.jl")
```

Workbench requires **Julia 1.12+** (workspace support).

## Quick start

From the root of your package:

```julia
julia> using Workbench

julia> Workbench.init(:dev)        # scaffold dev/ with a startup.jl

julia> Workbench.init(:benchmark)  # scaffold benchmark/ with a BenchmarkTools suite

julia> Workbench.add(:dev, "Infiltrator")  # add a dev dependency

julia> Workbench.activate(:dev)    # make dev deps available for `using`

julia> Workbench.status()          # see what's set up
```

## Workspace management

These operations create, configure, and run workspace sub-projects.

### `init` — scaffold a sub-project

```julia
Workbench.init(:dev)
Workbench.init(:benchmark)
Workbench.init(:docs)
Workbench.init(:myscripts)  # custom — gets a run.jl template
```

`init` creates the directory, generates a `Project.toml` with the parent package in `[deps]` + `[sources]`, writes a convention-appropriate entry-point file (never overwrites existing files), registers the sub-project under `[workspace].projects`, and installs default dependencies. It is idempotent — calling it twice produces the same project state.

### `add` / `rm` — manage sub-project dependencies

```julia
Workbench.add(:dev, "KaimonGate")
Workbench.add(:benchmark, "BenchmarkTools", "Statistics")
Workbench.rm(:dev, "KaimonGate")
```

Thin wrappers around `Pkg.add`/`Pkg.rm` that target the sub-project's environment. Your root project stays active afterward — `Pkg.activate(f, path)` handles the save/restore.

### `activate` / `deactivate` — dev-tool loading

This is Workbench's most important feature, and how it differs from simply running `pkg> activate dev`:

```julia
Workbench.activate(:dev)
```

This pushes the `:dev` sub-project onto `LOAD_PATH` so its dependencies become available for `using` — **without changing which project Pkg operations target.** Your root project remains the active Pkg environment:

```
Pkg operations          LOAD_PATH (for `using`)
      ↓                         ↓
  root package           1. @ (root project)
                         2. dev/ environment  ← stacked here
                         3. @v1.12
                         4. @stdlib
```

So you can do:

```julia
julia> Workbench.activate(:dev)
julia> using Infiltrator           # resolves from dev/
julia> Pkg.add("NewDep")           # still targets the root package
```

This is a meaningfully better experience than `pkg> activate dev`, which would redirect all subsequent `Pkg` operations to the dev environment.

If `dev/startup.jl` exists, it is executed in `Main` after activation — the same semantics as Julia's own `~/.julia/config/startup.jl`. This is where you put `using KaimonGate; KaimonGate.serve()` or similar dev-tool setup.

```julia
Workbench.activate(:dev; force=true)  # re-run startup.jl after editing it
Workbench.deactivate(:dev)            # pop :dev off LOAD_PATH
Workbench.deactivate()                # deactivate everything
```

#### Global startup hook

To auto-activate `:dev` whenever you start Julia inside a package with a `dev/` directory:

```julia
# ~/.julia/config/startup.jl
try
    using Workbench
catch
    # Workbench not installed — skip
end
if @isdefined(Workbench)
    Workbench.activate(:dev; quiet=true)
end
```

The `try/catch` is scoped tightly to `using Workbench` so only "not installed" is silenced. `quiet=true` handles the rest — if there's no package root, no `dev/` directory, or no `dev/Project.toml`, it silently returns `nothing`. If `startup.jl` throws, quiet mode suppresses the error (logged at `@debug` level). Real Workbench bugs propagate normally.

### `run` — execute a sub-project's entry point

```julia
Workbench.run(:test)         # delegates to Pkg.test()
Workbench.run(:benchmark)    # spawns julia --project=benchmark benchmarks.jl
Workbench.run(:docs)         # spawns julia --project=docs make.jl
Workbench.run(:myscripts)    # spawns julia --project=myscripts run.jl
```

`:test` delegates to Julia's native `Pkg.test()`; other sub-projects run their entry points in isolated subprocesses with `--project=<subdir> --startup-file=no`. This gives a strong isolation boundary — the subprocess isn't contaminated by whatever the developer has loaded in their REPL.

stdout/stderr are inherited for live output. The current session's thread count is forwarded by default:

```julia
Workbench.run(:benchmark; threads=8)       # override thread count
Workbench.run(:benchmark; threads=nothing)  # use subprocess default
Workbench.run(:myscripts; args=`--quick`)   # forward arguments to the script
```

### `status` — inspect the workspace

```julia
Workbench.status()
```

Prints each discovered sub-project with its state: Project.toml presence, workspace registration, entry point, activation status, and available actions. Warns about inconsistencies — a sub-project registered in the workspace but whose directory is missing, or a directory with a Project.toml that isn't registered.

## Package utilities

### `example` — run scripts from `examples/`

```julia
Workbench.example("basic")
```

Runs `examples/<name>.jl` in a subprocess with the **root** project active. Examples are not workspace members — they use the parent package directly.

## Conventions

| Name         | Directory      | Entry point     | Default deps    | Compatible with   |
|--------------|----------------|-----------------|-----------------|-------------------|
| `:test`      | `test/`        | `runtests.jl`   | Test            | `Pkg.test()`      |
| `:docs`      | `docs/`        | `make.jl`       | Documenter      | Documenter.jl     |
| `:benchmark` | `benchmark/`   | `benchmarks.jl` | BenchmarkTools  | PkgBenchmark.jl   |
| `:dev`       | `dev/`         | `startup.jl`    | —               | —                 |
| custom       | `<name>/`      | `run.jl`        | —               | —                 |

Workbench also recognizes `benchmarks/` (plural) as an alias for the `:benchmark` convention.

## Error handling

All Workbench-specific errors throw `Workbench.WorkbenchError`, so you can distinguish them from unrelated failures:

```julia
try
    Workbench.activate(:dev)
catch e
    e isa Workbench.WorkbenchError && @warn "Workbench issue" e
end
```

Invalid arguments (e.g. calling `add` with no package names) throw `ArgumentError`.

## Known limitations

- **TOML formatting**: `init` and `add_to_workspace!` rewrite `Project.toml` through Julia's TOML serializer, which normalizes formatting. If you hand-format your `Project.toml`, the first `init` call will rewrite it into canonical form. Subsequent calls are idempotent.
- **Julia 1.12+ required**: Workspaces are a Julia 1.12 feature. Workbench cannot be used with earlier Julia versions.

## License

See [LICENSE](LICENSE).
