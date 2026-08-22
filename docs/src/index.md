```@meta
CurrentModule = Workbench
```

# Workbench.jl

Workbench provides a development workspace manager for Julia packages. It scaffolds and manages sub-projects (`test/`, `docs/`, `benchmark/`, `dev/`, and custom task directories) as [workspace](https://pkgdocs.julialang.org/v1/toml-files/#Project-and-Manifest) members that share a single `Manifest.toml` with your package.

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

julia> Workbench.init(:dev)                    # scaffold dev/ with startup.jl

julia> Workbench.add(:dev, "Infiltrator")      # add a dev dependency

julia> Workbench.activate(:dev)                # make dev deps available

julia> Workbench.status()                      # inspect the workspace
```

## How it works

Julia 1.12 introduced workspaces — a mechanism for multiple sub-projects to share a single `Manifest.toml`. Workbench automates the creation and management of these workspace sub-projects.

### LOAD\_PATH stacking

The key feature of `activate` is that it pushes the sub-project onto `LOAD_PATH` **without changing the active Pkg project**:

```julia
julia> Workbench.activate(:dev)
julia> using Infiltrator           # resolves from dev/
julia> Pkg.add("NewDep")           # still targets the root package
```

This is different from `pkg> activate dev`, which would redirect all subsequent `Pkg` operations to the dev environment.

### Subprocess isolation

`run` spawns a fresh Julia process with `--project=<subdir> --startup-file=no`, giving a clean isolation boundary. The subprocess isn't contaminated by whatever the developer has loaded in their REPL. This is particularly important for benchmarks, where stray loaded code can affect results.

## Conventions

| Name         | Directory      | Entry point     | Default deps    | Compatible with   |
|:-------------|:---------------|:----------------|:----------------|:------------------|
| `:test`      | `test/`        | `runtests.jl`   | Test            | `Pkg.test()`      |
| `:docs`      | `docs/`        | `make.jl`       | Documenter      | Documenter.jl     |
| `:benchmark` | `benchmark/`   | `benchmarks.jl` | BenchmarkTools  | PkgBenchmark.jl   |
| `:dev`       | `dev/`         | `startup.jl`    | —               | —                 |
| custom       | `<name>/`      | `run.jl`        | —               | —                 |

`benchmarks/` (plural) is also recognized as an alias for the `:benchmark` convention.

`:test` is a special case — `Workbench.run(:test)` delegates to Julia's native `Pkg.test()` rather than spawning its own subprocess.

## Global startup hook

To auto-activate `:dev` whenever you start Julia inside a package:

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

`quiet=true` silently returns `nothing` when there's no package root, no `dev/` directory, or no `dev/Project.toml`. Startup script errors are suppressed (logged at `@debug`). Real Workbench bugs propagate normally.

## Error handling

All Workbench-specific errors throw [`WorkbenchError`](@ref), so you can distinguish them from unrelated failures. Invalid arguments (e.g. calling `add` with no package names) throw `ArgumentError`.

## API Reference

```@docs
WorkbenchError
init
add
rm
activate
deactivate
run
example
status
find_project_root
discover
discover_examples
SubProject
```
