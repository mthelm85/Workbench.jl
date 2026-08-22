# ── Discovery ────────────────────────────────────────────────────────────────
#
# Locate the project root and enumerate sub-projects by convention + workspace.

# Well-known sub-project conventions: name => entry point filename
const CONVENTIONS = Dict{Symbol,String}(
    :test      => "runtests.jl",
    :docs      => "make.jl",
    :benchmark => "benchmarks.jl",
    :dev       => "startup.jl",
)

# Common directory-name aliases that map to a canonical convention.
# e.g. "benchmarks/" on disk is treated as the :benchmark convention.
const _DIR_ALIASES = Dict{String,Symbol}(
    "benchmarks" => :benchmark,
)

"""
    _safe_parsefile(path) -> Dict{String,Any}

Parse a TOML file, wrapping parse errors with the file path for context.
Returns an empty dict if the file does not exist.
"""
function _safe_parsefile(path::AbstractString)
    isfile(path) || return Dict{String,Any}()
    try
        TOML.parsefile(path)
    catch e
        if e isa TOML.ParserError
            throw(WorkbenchError("Failed to parse $(path): $(sprint(showerror, e))"))
        end
        rethrow()
    end
end

"""
    find_project_root(start=pwd()) -> String

Walk up from `start` looking for a `Project.toml` that has both `name` and `uuid`
fields (i.e. a real package, not a sub-project or environment).

Throws `WorkbenchError` if no package root is found.
"""
function find_project_root(start::AbstractString=pwd())
    dir = abspath(start)
    while true
        toml_path = joinpath(dir, "Project.toml")
        if isfile(toml_path)
            d = _safe_parsefile(toml_path)
            if haskey(d, "name") && haskey(d, "uuid")
                return dir
            end
        end
        parent = dirname(dir)
        if parent == dir
            throw(WorkbenchError(
                "No package Project.toml (with name and uuid) found above $(start). " *
                "Run Workbench from inside a Julia package directory."))
        end
        dir = parent
    end
end

"""
    discover(root=find_project_root()) -> Dict{Symbol, SubProject}

Scan for sub-projects by:
1. Well-known conventions (test/, docs/, benchmark/, dev/)
2. Entries in `[workspace].projects` in the root Project.toml
3. Any other directory containing a `run.jl` (custom tasks)

Directories that exist but lack a Project.toml are still returned —
`init()` can wire them up later.
"""
function discover(root::AbstractString=find_project_root())
    result = Dict{Symbol,SubProject}()

    root_toml = _safe_parsefile(joinpath(root, "Project.toml"))

    # Workspace members listed in root Project.toml
    workspace_members = Set{String}()
    if haskey(root_toml, "workspace")
        ws = root_toml["workspace"]
        if haskey(ws, "projects")
            projects = ws["projects"]
            if projects isa AbstractVector
                for p in projects
                    p isa AbstractString && push!(workspace_members, p)
                end
            end
        end
    end

    # 1. Scan well-known convention directories (canonical names first)
    for (name, entry) in CONVENTIONS
        dir = joinpath(root, String(name))
        isdir(dir) || continue
        has_toml = isfile(joinpath(dir, "Project.toml"))
        entry_path = joinpath(dir, entry)
        ep = isfile(entry_path) ? entry_path : nothing
        in_ws = String(name) in workspace_members
        result[name] = SubProject(name, dir, has_toml, ep, in_ws)
    end

    # 1b. Check directory-name aliases (e.g. "benchmarks/" → :benchmark)
    for (alias, canonical) in _DIR_ALIASES
        haskey(result, canonical) && continue  # canonical dir already found
        dir = joinpath(root, alias)
        isdir(dir) || continue
        entry = CONVENTIONS[canonical]
        has_toml = isfile(joinpath(dir, "Project.toml"))
        entry_path = joinpath(dir, entry)
        ep = isfile(entry_path) ? entry_path : nothing
        in_ws = alias in workspace_members
        result[canonical] = SubProject(canonical, dir, has_toml, ep, in_ws)
    end

    # 2. Scan workspace members not already covered
    for member in workspace_members
        sym = Symbol(member)
        haskey(result, sym) && continue
        dir = joinpath(root, member)
        isdir(dir) || continue
        has_toml = isfile(joinpath(dir, "Project.toml"))
        # Custom tasks use run.jl
        run_jl = joinpath(dir, "run.jl")
        ep = isfile(run_jl) ? run_jl : nothing
        result[sym] = SubProject(sym, dir, has_toml, ep, true)
    end

    # 3. Scan for examples/ (special: not a workspace member)
    examples_dir = joinpath(root, "examples")
    if isdir(examples_dir) && !haskey(result, :examples)
        result[:examples] = SubProject(:examples, examples_dir, false, nothing, false)
    end

    result
end

"""
    discover_examples(root=find_project_root()) -> Vector{String}

List available example scripts (basenames without `.jl` extension).
"""
function discover_examples(root::AbstractString=find_project_root())
    examples_dir = joinpath(root, "examples")
    isdir(examples_dir) || return String[]
    names = String[]
    for f in readdir(examples_dir)
        endswith(f, ".jl") || continue
        push!(names, f[1:end-3])
    end
    sort!(names)
end
