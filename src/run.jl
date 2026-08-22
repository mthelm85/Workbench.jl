# ── Task running ─────────────────────────────────────────────────────────────
#
# Spawn a Julia subprocess with --project=<subdir> to run task entry points.
# Like `] test`, but generalized to any sub-project.

# Resolve the Julia executable — same binary running the current session
_julia_cmd() = joinpath(Sys.BINDIR, "julia")

"""
    run(name::Symbol; root=find_project_root(), args=``, threads=Threads.nthreads())

Run a sub-project's entry-point script in a subprocess.

- `:test` delegates to `Pkg.test()` (matches `] test` behavior)
- Other sub-projects spawn `julia --project=<subdir> --startup-file=no <entry_point>`
- stdout/stderr are inherited for live output
- By default, the current session's thread count is forwarded to the
  subprocess via `--threads`. Pass `threads=nothing` to omit the flag
  (use the subprocess's own default), or an `Int`/`:auto` to override.

# Examples
```julia
Workbench.run(:test)
Workbench.run(:benchmark)
Workbench.run(:benchmark; threads=8)
Workbench.run(:docs)
Workbench.run(:myscripts)
```
"""
function run(name::Symbol; root::AbstractString=find_project_root(), args::Cmd=``,
             threads::Union{Integer,Symbol,Nothing}=Base.Threads.nthreads())
    thread_args = threads === nothing ? `` : `--threads=$threads`

    # Special case: :test delegates to Pkg.test()
    if name === :test
        @info "Running tests via Pkg.test()..." threads
        try
            Pkg.test(; julia_args=thread_args)
        catch e
            e isa WorkbenchError && rethrow()
            throw(WorkbenchError(
                "Tests failed. See output above for details."))
        end
        return nothing
    end

    subdir = joinpath(root, String(name))
    if !isdir(subdir)
        throw(WorkbenchError(
            "Sub-project :$name not found at $(subdir). " *
            "Run Workbench.init(:$name) first."))
    end

    # Find entry point
    convention = get(CONVENTIONS, name, nothing)
    entry_file = convention !== nothing ? convention : "run.jl"
    entry_path = joinpath(subdir, entry_file)
    if !isfile(entry_path)
        throw(WorkbenchError(
            "Entry point not found: $(entry_path). " *
            "Expected $(entry_file) in $(subdir)."))
    end

    julia = _julia_cmd()
    cmd = `$julia --project=$subdir --startup-file=no $thread_args $entry_path $args`

    @info "Running :$name" command=cmd
    try
        Base.run(cmd)
    catch e
        if e isa ProcessFailedException
            throw(WorkbenchError(
                ":$name failed (non-zero exit code). See output above for details."))
        end
        throw(WorkbenchError(
            "Failed to run :$name: $(sprint(showerror, e))"))
    end

    nothing
end

"""
    example(name::AbstractString; root=find_project_root(), args=``)

Run an example script from the `examples/` directory with the root project active.
Examples are not workspace members — they use the parent package directly.

# Examples
```julia
Workbench.example("basic")
Workbench.example("advanced")
```
"""
function example(name::AbstractString; root::AbstractString=find_project_root(), args::Cmd=``)
    examples_dir = joinpath(root, "examples")
    if !isdir(examples_dir)
        throw(WorkbenchError("No examples/ directory found in $(root)."))
    end

    script = joinpath(examples_dir, name * ".jl")
    if !isfile(script)
        available = discover_examples(root)
        hint = isempty(available) ? "" : " Available: $(join(available, ", "))"
        throw(WorkbenchError("Example \"$name\" not found at $(script).$hint"))
    end

    julia = _julia_cmd()
    cmd = `$julia --project=$root --startup-file=no $script $args`

    @info "Running example: $name" command=cmd
    try
        Base.run(cmd)
    catch e
        if e isa ProcessFailedException
            throw(WorkbenchError(
                "Example \"$name\" failed (non-zero exit code). See output above for details."))
        end
        throw(WorkbenchError(
            "Failed to run example \"$name\": $(sprint(showerror, e))"))
    end

    nothing
end
