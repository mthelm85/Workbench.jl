# ── Scaffolding ──────────────────────────────────────────────────────────────
#
# `init(name)` creates a sub-project directory, generates a Project.toml
# (with parent in [deps]+[sources]), writes a convention entry-point template,
# and wires up the workspace.

# Templates for well-known sub-project entry points.
# Each returns the file content as a string.
const _TEMPLATES = Dict{Symbol,Function}(
    :benchmark => (pkg) -> """
        using BenchmarkTools
        using $pkg

        const SUITE = BenchmarkGroup()

        # SUITE["group"] = @benchmarkable ...

        # Run with: tune!(SUITE); results = run(SUITE)
        """,

    :docs => (pkg) -> """
        using Documenter
        using $pkg

        makedocs(;
            sitename = "$pkg",
            modules = [$pkg],
            pages = ["Home" => "index.md"],
        )
        """,

    :dev => (_) -> """
        # Dev startup script — runs when `Workbench.activate(:dev)` is called.
        # Add your dev-time tool imports here, e.g.:
        # using KaimonGate; KaimonGate.serve()
        """,

    :test => (pkg) -> """
        using Test
        using $pkg

        @testset "$pkg" begin
            # Write your tests here.
        end
        """,
)

# Default deps to install for each convention
const _DEFAULT_DEPS = Dict{Symbol,Vector{String}}(
    :benchmark => ["BenchmarkTools"],
    :docs      => ["Documenter"],
    :test      => ["Test"],
    :dev       => String[],
)

"""
    init(name::Symbol; root=find_project_root())

Scaffold a sub-project workspace member.

- Creates the directory if it doesn't exist
- Generates `Project.toml` with parent package in `[deps]` + `[sources]`
- Writes a convention entry-point file (won't overwrite existing files)
- Adds the sub-project to `[workspace].projects` in the root `Project.toml`
- Installs default dependencies (e.g. BenchmarkTools for `:benchmark`)

# Examples
```julia
Workbench.init(:benchmark)
Workbench.init(:dev)
Workbench.init(:myscripts)  # custom — gets run.jl template
```
"""
function init(name::Symbol; root::AbstractString=find_project_root())
    subdir = joinpath(root, String(name))
    pname, puuid = parent_info(root)

    # Create directory
    try
        mkpath(subdir)
    catch e
        throw(WorkbenchError(
            "Failed to create directory $(subdir): $(sprint(showerror, e))"))
    end

    # Project.toml — create if missing, wire up sources if exists
    sub_toml = joinpath(subdir, "Project.toml")
    if !isfile(sub_toml)
        # Generate a fresh Project.toml
        data = Dict{String,Any}(
            "deps" => Dict{String,Any}(pname => puuid),
            "sources" => Dict{String,Any}(pname => Dict{String,Any}("path" => "..")),
        )
        write_toml(sub_toml, data)
        @info "Created $(sub_toml)"
    else
        # Existing Project.toml — just ensure parent is in deps/sources
        ensure_sources!(subdir, pname, puuid)
        @info "Wired parent into existing $(sub_toml)"
    end

    # Entry-point file — never overwrite
    convention = get(CONVENTIONS, name, nothing)
    entry_file = convention !== nothing ? convention : "run.jl"
    entry_path = joinpath(subdir, entry_file)

    if !isfile(entry_path)
        template_fn = get(_TEMPLATES, name, nothing)
        content = if template_fn !== nothing
            template_fn(pname)
        else
            # Custom sub-project
            """
            # Custom task entry point for :$name
            # Run with: Workbench.run(:$name)
            using $pname

            println("Running :$name task...")
            """
        end
        try
            write(entry_path, content)
        catch e
            throw(WorkbenchError(
                "Failed to write $(entry_path): $(sprint(showerror, e))"))
        end
        @info "Created $(entry_path)"

        # Also create docs/src/index.md for Documenter compatibility
        if name === :docs
            src_dir = joinpath(subdir, "src")
            index_path = joinpath(src_dir, "index.md")
            if !isdir(src_dir)
                mkpath(src_dir)
            end
            if !isfile(index_path)
                Base.write(index_path, """
                    # $pname.jl

                    Documentation for $pname.
                    """)
                @info "Created $(index_path)"
            end
        end
    end

    # Wire up workspace
    add_to_workspace!(root, String(name))

    # Install default dependencies
    default_deps = get(_DEFAULT_DEPS, name, String[])
    try
        if !isempty(default_deps)
            @info "Installing default dependencies: $(join(default_deps, ", "))"
            Pkg.activate(subdir) do
                Pkg.add(default_deps)
            end
        else
            # Still resolve to generate/update the shared Manifest
            Pkg.activate(subdir) do
                Pkg.resolve()
            end
        end
    catch e
        e isa WorkbenchError && rethrow()
        throw(WorkbenchError(
            "Failed to resolve dependencies for :$name at $(subdir). " *
            "The directory and Project.toml were created, but Pkg operations failed: " *
            "$(sprint(showerror, e))"))
    end

    @info "Sub-project :$name is ready at $(subdir)"
    nothing
end
