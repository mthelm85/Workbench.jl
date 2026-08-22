# ── TOML helpers ─────────────────────────────────────────────────────────────
#
# Read-modify-write operations on Project.toml files.
# Uses TOML stdlib directly — no Pkg.Types internals.

"""
    write_toml(path, data)

Write a TOML dict to `path`, preserving standard Pkg key ordering.
Writes to a temp file and renames into place so a crash or concurrent
write can't leave `path` truncated or corrupted.
"""
function write_toml(path::AbstractString, data::Dict)
    # Pkg's conventional key order
    key_order = ["name", "uuid", "version", "authors",
                 "deps", "sources", "workspace",
                 "compat", "extras", "targets"]

    dir = dirname(path)
    tmp = tempname(isempty(dir) ? "." : dir; cleanup=false)
    try
        open(tmp, "w") do io
            TOML.print(io, data; sorted=false) do key
                idx = findfirst(==(key), key_order)
                idx === nothing ? (length(key_order) + 1, key) : (idx, key)
            end
        end
        mv(tmp, path; force=true)
    catch e
        Base.rm(tmp; force=true)
        if e isa SystemError
            throw(WorkbenchError("Failed to write $(path): $(sprint(showerror, e))"))
        end
        rethrow()
    end
end

"""
    add_to_workspace!(root, subdir_name)

Ensure `subdir_name` appears in `[workspace].projects` in the root Project.toml.
Creates the `[workspace]` section if missing. Idempotent.
"""
function add_to_workspace!(root::AbstractString, subdir_name::AbstractString)
    toml_path = joinpath(root, "Project.toml")
    data = _safe_parsefile(toml_path)

    if !haskey(data, "workspace")
        data["workspace"] = Dict{String,Any}("projects" => String[])
    end
    ws = data["workspace"]
    if !haskey(ws, "projects")
        ws["projects"] = String[]
    end

    projects = ws["projects"]
    if subdir_name ∉ projects
        push!(projects, subdir_name)
        sort!(projects)
        write_toml(toml_path, data)
        @info "Added \"$subdir_name\" to [workspace].projects"
    end
end

"""
    ensure_sources!(subdir_path, parent_name, parent_uuid)

Ensure the sub-project's Project.toml has the parent package in both
`[deps]` and `[sources]` (with `path = ".."`). Idempotent.
"""
function ensure_sources!(subdir_path::AbstractString,
                          parent_name::AbstractString,
                          parent_uuid::AbstractString)
    toml_path = joinpath(subdir_path, "Project.toml")
    data = _safe_parsefile(toml_path)

    # [deps] — add parent
    if !haskey(data, "deps")
        data["deps"] = Dict{String,Any}()
    end
    data["deps"][parent_name] = parent_uuid

    # [sources] — add path back-reference
    if !haskey(data, "sources")
        data["sources"] = Dict{String,Any}()
    end
    data["sources"][parent_name] = Dict{String,Any}("path" => "..")

    write_toml(toml_path, data)
end

"""
    parent_info(root) -> (name::String, uuid::String)

Read the parent package's name and uuid from its Project.toml.
Throws `WorkbenchError` if the file is missing or lacks required fields.
"""
function parent_info(root::AbstractString)
    toml_path = joinpath(root, "Project.toml")
    isfile(toml_path) || throw(WorkbenchError("Project.toml not found at $(toml_path)"))

    data = _safe_parsefile(toml_path)

    name = get(data, "name", nothing)
    uuid = get(data, "uuid", nothing)
    if name === nothing || uuid === nothing
        missing_fields = String[]
        name === nothing && push!(missing_fields, "name")
        uuid === nothing && push!(missing_fields, "uuid")
        throw(WorkbenchError(
            "Project.toml at $(toml_path) is missing required fields: $(join(missing_fields, ", ")). " *
            "Workbench operates on Julia packages, not plain environments."))
    end
    (name::String, uuid::String)
end
