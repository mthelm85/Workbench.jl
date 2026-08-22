# ── Dependency management ────────────────────────────────────────────────────
#
# Thin wrappers around Pkg.add/rm that target sub-project environments.
# Uses Pkg.activate(f, path) block form — public API, auto-restores root project.

"""
    _resolve_subdir(name, root) -> String

Validate that a sub-project directory exists and has a Project.toml.
Returns the absolute path. Throws `WorkbenchError` on failure.
"""
function _resolve_subdir(name::Symbol, root::AbstractString)
    subdir = joinpath(root, String(name))
    if !isdir(subdir)
        throw(WorkbenchError(
            "Sub-project :$name not found at $(subdir). " *
            "Run Workbench.init(:$name) first."))
    end
    if !isfile(joinpath(subdir, "Project.toml"))
        throw(WorkbenchError(
            "No Project.toml in $(subdir). " *
            "Run Workbench.init(:$name) to create one."))
    end
    subdir
end

"""
    add(name::Symbol, pkgs...; root=find_project_root())

Add packages to a sub-project's dependencies.

# Examples
```julia
Workbench.add(:dev, "KaimonGate")
Workbench.add(:benchmark, "BenchmarkTools", "Statistics")
```
"""
function add(name::Symbol, pkgs::AbstractString...; root::AbstractString=find_project_root())
    if isempty(pkgs)
        throw(ArgumentError(
            "No packages specified. Usage: Workbench.add(:$name, \"PkgName\")"))
    end
    subdir = _resolve_subdir(name, root)

    try
        Pkg.activate(subdir) do
            Pkg.add(collect(pkgs))
        end
    catch e
        e isa WorkbenchError && rethrow()
        e isa ArgumentError && rethrow()
        throw(WorkbenchError(
            "Failed to add $(join(pkgs, ", ")) to :$name: $(sprint(showerror, e))"))
    end
    @info "Added $(join(pkgs, ", ")) to :$name"
    nothing
end

"""
    rm(name::Symbol, pkgs...; root=find_project_root())

Remove packages from a sub-project's dependencies.

# Examples
```julia
Workbench.rm(:dev, "KaimonGate")
```
"""
function rm(name::Symbol, pkgs::AbstractString...; root::AbstractString=find_project_root())
    if isempty(pkgs)
        throw(ArgumentError(
            "No packages specified. Usage: Workbench.rm(:$name, \"PkgName\")"))
    end
    subdir = _resolve_subdir(name, root)

    try
        Pkg.activate(subdir) do
            Pkg.rm(collect(pkgs))
        end
    catch e
        e isa WorkbenchError && rethrow()
        e isa ArgumentError && rethrow()
        throw(WorkbenchError(
            "Failed to remove $(join(pkgs, ", ")) from :$name: $(sprint(showerror, e))"))
    end
    @info "Removed $(join(pkgs, ", ")) from :$name"
    nothing
end
