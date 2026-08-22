# ── Status display ───────────────────────────────────────────────────────────
#
# Pretty-print discovered sub-projects and their state.

"""
    status(; root=find_project_root(), io=stdout)

Display all discovered sub-projects, their state, and available actions.

Shows:
- Whether each sub-project has a Project.toml
- Whether it's registered in the workspace
- Its entry point (if any)
- Whether it's currently activated (LOAD_PATH stacked)
- Warnings for workspace/filesystem inconsistencies
- Available examples
"""
function status(; root::AbstractString=find_project_root(), io::IO=stdout)
    pname, _ = parent_info(root)
    subs = discover(root)

    println(io, "┌─ Workbench status for $pname")
    println(io, "│  Root: $root")
    println(io, "│")

    if isempty(subs)
        println(io, "│  No sub-projects found.")
        println(io, "│  Run Workbench.init(:dev) to get started.")
        println(io, "└─")
        return nothing
    end

    # Collect workspace members that reference missing directories
    root_toml = _safe_parsefile(joinpath(root, "Project.toml"))
    orphaned_members = String[]
    if haskey(root_toml, "workspace") && haskey(root_toml["workspace"], "projects")
        for member in root_toml["workspace"]["projects"]
            member isa AbstractString || continue
            if !isdir(joinpath(root, member))
                push!(orphaned_members, member)
            end
        end
    end

    # Sort: well-known first, then alphabetical
    known_order = [:test, :docs, :benchmark, :dev, :examples]
    names = collect(keys(subs))
    sort!(names; by = n -> begin
        idx = findfirst(==(n), known_order)
        idx !== nothing ? (1, idx, "") : (2, 0, String(n))
    end)

    for (i, name) in enumerate(names)
        sub = subs[name]
        is_last = i == length(names) && isempty(orphaned_members)
        prefix = is_last ? "└" : "├"
        cont   = is_last ? " " : "│"

        # Status indicators
        toml_icon = sub.has_project_toml ? "✓" : "✗"
        ws_icon   = sub.in_workspace ? "✓" : "✗"
        active    = haskey(_ACTIVATED, name)
        act_str   = active ? " [ACTIVE]" : ""

        println(io, "$(prefix)─ :$name$(act_str)")
        println(io, "$(cont)  Project.toml: $(toml_icon)  Workspace: $(ws_icon)")

        if sub.entry_point !== nothing
            ep_name = basename(sub.entry_point)
            println(io, "$(cont)  Entry: $(ep_name)")
        end

        # Warnings for inconsistent state
        if sub.has_project_toml && !sub.in_workspace && name !== :examples
            println(io, "$(cont)  ⚠ Has Project.toml but not in [workspace].projects")
        end
        if sub.in_workspace && !sub.has_project_toml
            println(io, "$(cont)  ⚠ In [workspace].projects but missing Project.toml")
        end

        # Show available actions
        actions = String[]
        if sub.has_project_toml
            if name === :dev
                push!(actions, "activate(:$name)")
            end
            if sub.entry_point !== nothing && name !== :examples
                push!(actions, "run(:$name)")
            end
            if !sub.in_workspace && name !== :examples
                push!(actions, "init(:$name)  # wire into workspace")
            end
        else
            push!(actions, "init(:$name)")
        end
        if !isempty(actions)
            println(io, "$(cont)  Actions: $(join(actions, ", "))")
        end

        if !is_last
            println(io, "│")
        end
    end

    # Orphaned workspace members (registered but directory missing)
    for (i, member) in enumerate(orphaned_members)
        is_last = i == length(orphaned_members)
        prefix = is_last ? "└" : "├"
        cont   = is_last ? " " : "│"
        println(io, "$(prefix)─ :$member")
        println(io, "$(cont)  ⚠ Listed in [workspace].projects but directory not found")
    end

    # Examples
    examples = discover_examples(root)
    if !isempty(examples)
        println(io)
        println(io, "  Examples: $(join(examples, ", "))")
        println(io, "  Run with: Workbench.example(\"name\")")
    end

    nothing
end
