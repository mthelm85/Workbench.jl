module Workbench

using Pkg
using TOML
using UUIDs: uuid4

# ── Errors ───────────────────────────────────────────────────────────────────

"""
    WorkbenchError <: Exception

Thrown for all Workbench-specific failures: missing project roots, missing
sub-project directories, TOML issues, subprocess failures, etc.

Catch this type to distinguish Workbench problems from unrelated exceptions:

```julia
try
    Workbench.activate(:dev)
catch e
    e isa Workbench.WorkbenchError && @warn "Workbench issue" e
end
```
"""
struct WorkbenchError <: Exception
    msg::String
end

Base.showerror(io::IO, e::WorkbenchError) = print(io, "WorkbenchError: ", e.msg)

# ── Types ────────────────────────────────────────────────────────────────────

"""
    SubProject

Metadata for a discovered sub-project (workspace member or convention directory).
"""
struct SubProject
    name::Symbol
    path::String
    has_project_toml::Bool
    entry_point::Union{String,Nothing}
    in_workspace::Bool
end

# ── Module state ─────────────────────────────────────────────────────────────

"""Tracks activated sub-projects: name => absolute path pushed onto LOAD_PATH."""
const _ACTIVATED = Dict{Symbol,String}()

# ── Includes ─────────────────────────────────────────────────────────────────

include("discover.jl")
include("toml.jl")
include("scaffold.jl")
include("deps.jl")
include("activate.jl")
include("run.jl")
include("status.jl")

# ── Public API ───────────────────────────────────────────────────────────────

export init, add, rm, activate, deactivate, run, example, status

end # module Workbench
