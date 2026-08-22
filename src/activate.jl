# ── Activation ───────────────────────────────────────────────────────────────
#
# Push a sub-project onto LOAD_PATH so its deps are available for `using`
# without changing which project Pkg operations target.
#
# Safe with workspaces: all sub-projects share one Manifest, so no version
# conflicts can arise from stacking.

"""
    activate(name::Symbol; root=find_project_root(), quiet=false, force=false)

Make a sub-project's dependencies available in the current REPL session by
pushing its environment onto `LOAD_PATH`.

If a `startup.jl` (for `:dev`) exists, it is executed afterward — in `Main`,
so `using X` resolves via the stacked `LOAD_PATH` just like a normal startup
file.

Pass `quiet=true` to silently return `nothing` when there's no package root,
no sub-project directory, or no Project.toml — and to suppress any errors from
the startup script. This is designed for global startup hooks.

Pass `force=true` to re-run the startup script even if the sub-project is
already activated (e.g. after editing `startup.jl`).

# Examples
```julia
Workbench.activate(:dev)
Workbench.activate(:dev; quiet=true)  # for startup.jl hooks
Workbench.activate(:dev; force=true)  # re-run startup.jl after editing it
```
"""
function activate(name::Symbol; root::Union{AbstractString,Nothing}=nothing,
                  quiet::Bool=false, force::Bool=false)
    # Resolve root — in quiet mode, silently return if we're not in a package dir
    if root === nothing
        try
            root = find_project_root()
        catch e
            if quiet && e isa WorkbenchError
                return nothing
            end
            rethrow()
        end
    end

    already_activated = haskey(_ACTIVATED, name)
    if already_activated && !force
        quiet || @info ":$name is already activated"
        return nothing
    end

    subdir = joinpath(root, String(name))
    if !isdir(subdir)
        quiet && return nothing
        throw(WorkbenchError(
            "Sub-project :$name not found at $(subdir). " *
            "Run Workbench.init(:$name) first."))
    end
    if !isfile(joinpath(subdir, "Project.toml"))
        quiet && return nothing
        throw(WorkbenchError(
            "No Project.toml in $(subdir). " *
            "Run Workbench.init(:$name) to create one."))
    end

    subdir_abs = abspath(subdir)

    if already_activated
        quiet || @info "Re-running startup script for :$name"
    else
        # Push onto LOAD_PATH at position 2 (after "@" which is the active project)
        # This makes the sub-project's deps available for `using`
        at_idx = findfirst(==("@"), LOAD_PATH)
        insert_pos = at_idx !== nothing ? at_idx + 1 : 2
        insert!(LOAD_PATH, insert_pos, subdir_abs)

        _ACTIVATED[name] = subdir_abs
        quiet || @info "Activated :$name — its dependencies are now available"
    end

    # Run startup script if present
    startup = _startup_script(name, subdir)
    if startup !== nothing && isfile(startup)
        try
            # include into Main so `using X` resolves via LOAD_PATH (the stacked
            # sub-project env), not via Workbench's own package dependencies
            Base.include(Main, startup)
        catch e
            if quiet
                @debug "Startup script failed (quiet mode)" name exception=e
            else
                @warn "Startup script error" script=startup exception=(e, catch_backtrace())
            end
        end
    end

    nothing
end

"""
    deactivate(name::Symbol)
    deactivate()

Remove a sub-project from `LOAD_PATH`. With no arguments, deactivates all.
"""
function deactivate(name::Symbol)
    path = pop!(_ACTIVATED, name, nothing)
    if path !== nothing
        filter!(!=(path), LOAD_PATH)
        @info "Deactivated :$name"
    else
        @info ":$name was not activated"
    end
    nothing
end

function deactivate()
    for (name, path) in _ACTIVATED
        filter!(!=(path), LOAD_PATH)
        @info "Deactivated :$name"
    end
    empty!(_ACTIVATED)
    nothing
end

# Determine which script to run on activation
function _startup_script(name::Symbol, subdir::AbstractString)
    if name === :dev
        return joinpath(subdir, "startup.jl")
    end
    # Don't auto-run entry points for task-oriented sub-projects
    # (benchmark, docs, test run via `Workbench.run`, not `activate`)
    return nothing
end
