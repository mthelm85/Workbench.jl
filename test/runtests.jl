using Workbench
using Test
using Aqua
using JET
using TOML
using UUIDs: uuid4

@testset "Workbench.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(Workbench)
    end
    @testset "Code linting (JET.jl)" begin
        JET.test_package(Workbench; target_modules=[Workbench])
    end

    # ── Helper: create a fake package in a temp directory ─────────────────
    function make_fake_pkg(dir; name="FakePkg")
        uuid = string(uuid4())
        toml = Dict(
            "name" => name,
            "uuid" => uuid,
            "version" => "0.1.0",
        )
        open(joinpath(dir, "Project.toml"), "w") do io
            TOML.print(io, toml)
        end
        mkpath(joinpath(dir, "src"))
        write(joinpath(dir, "src", "$name.jl"), "module $name\nend\n")
        return (name=name, uuid=uuid)
    end

    # ── WorkbenchError ───────────────────────────────────────────────────
    @testset "WorkbenchError" begin
        e = Workbench.WorkbenchError("test message")
        @test e isa Exception
        @test sprint(showerror, e) == "WorkbenchError: test message"
    end

    # ── Discovery ────────────────────────────────────────────────────────
    @testset "find_project_root" begin
        mktempdir() do dir
            make_fake_pkg(dir)
            # From the root itself
            @test Workbench.find_project_root(dir) == dir

            # From a subdirectory
            sub = joinpath(dir, "src")
            @test Workbench.find_project_root(sub) == dir

            # From a deeper subdirectory
            deep = joinpath(dir, "src", "nested")
            mkpath(deep)
            @test Workbench.find_project_root(deep) == dir
        end

        # No package found — throws WorkbenchError
        mktempdir() do dir
            @test_throws Workbench.WorkbenchError Workbench.find_project_root(dir)
        end

        # Project.toml without name/uuid (plain environment) — not a package root
        mktempdir() do dir
            write(joinpath(dir, "Project.toml"), "[deps]\n")
            @test_throws Workbench.WorkbenchError Workbench.find_project_root(dir)
        end
    end

    @testset "discover" begin
        mktempdir() do dir
            pkg = make_fake_pkg(dir)

            # No sub-projects yet
            subs = Workbench.discover(dir)
            @test isempty(subs)

            # Create a test/ directory (no Project.toml)
            test_dir = joinpath(dir, "test")
            mkpath(test_dir)
            subs = Workbench.discover(dir)
            @test haskey(subs, :test)
            @test subs[:test].has_project_toml == false
            @test subs[:test].entry_point === nothing

            # Add runtests.jl
            write(joinpath(test_dir, "runtests.jl"), "using Test\n")
            subs = Workbench.discover(dir)
            @test subs[:test].entry_point == joinpath(test_dir, "runtests.jl")

            # Create benchmark/ with Project.toml
            bench_dir = joinpath(dir, "benchmark")
            mkpath(bench_dir)
            write(joinpath(bench_dir, "Project.toml"), "[deps]\n")
            write(joinpath(bench_dir, "benchmarks.jl"), "# bench\n")
            subs = Workbench.discover(dir)
            @test haskey(subs, :benchmark)
            @test subs[:benchmark].has_project_toml == true
            @test subs[:benchmark].entry_point == joinpath(bench_dir, "benchmarks.jl")

            # Workspace members show up
            root_toml = TOML.parsefile(joinpath(dir, "Project.toml"))
            root_toml["workspace"] = Dict("projects" => ["benchmark", "custom"])
            open(joinpath(dir, "Project.toml"), "w") do io
                TOML.print(io, root_toml)
            end
            custom_dir = joinpath(dir, "custom")
            mkpath(custom_dir)
            write(joinpath(custom_dir, "run.jl"), "# custom\n")
            subs = Workbench.discover(dir)
            @test haskey(subs, :custom)
            @test subs[:custom].in_workspace == true
            @test subs[:custom].entry_point == joinpath(custom_dir, "run.jl")
            @test subs[:benchmark].in_workspace == true
        end
    end

    @testset "discover with benchmarks/ alias" begin
        mktempdir() do dir
            make_fake_pkg(dir)
            # "benchmarks/" (plural) should map to :benchmark
            bench_dir = joinpath(dir, "benchmarks")
            mkpath(bench_dir)
            write(joinpath(bench_dir, "Project.toml"), "[deps]\n")
            write(joinpath(bench_dir, "benchmarks.jl"), "# bench\n")
            subs = Workbench.discover(dir)
            @test haskey(subs, :benchmark)
            @test subs[:benchmark].path == bench_dir
        end

        mktempdir() do dir
            make_fake_pkg(dir)
            # Canonical "benchmark/" takes precedence over "benchmarks/"
            mkpath(joinpath(dir, "benchmark"))
            mkpath(joinpath(dir, "benchmarks"))
            subs = Workbench.discover(dir)
            @test haskey(subs, :benchmark)
            @test subs[:benchmark].path == joinpath(dir, "benchmark")
        end
    end

    @testset "discover_examples" begin
        mktempdir() do dir
            make_fake_pkg(dir)

            # No examples dir
            @test isempty(Workbench.discover_examples(dir))

            # Create examples
            ex_dir = joinpath(dir, "examples")
            mkpath(ex_dir)
            write(joinpath(ex_dir, "basic.jl"), "# basic\n")
            write(joinpath(ex_dir, "advanced.jl"), "# advanced\n")
            write(joinpath(ex_dir, "README.md"), "# not a script\n")

            examples = Workbench.discover_examples(dir)
            @test examples == ["advanced", "basic"]  # sorted
        end
    end

    # ── TOML helpers ─────────────────────────────────────────────────────
    @testset "toml helpers" begin
        mktempdir() do dir
            pkg = make_fake_pkg(dir)

            # add_to_workspace! — creates [workspace] section
            Workbench.add_to_workspace!(dir, "benchmark")
            data = TOML.parsefile(joinpath(dir, "Project.toml"))
            @test "benchmark" in data["workspace"]["projects"]

            # Idempotent — no duplicate
            Workbench.add_to_workspace!(dir, "benchmark")
            data = TOML.parsefile(joinpath(dir, "Project.toml"))
            @test count(==("benchmark"), data["workspace"]["projects"]) == 1

            # Add another — sorted
            Workbench.add_to_workspace!(dir, "dev")
            data = TOML.parsefile(joinpath(dir, "Project.toml"))
            @test data["workspace"]["projects"] == ["benchmark", "dev"]

            # ensure_sources!
            sub = joinpath(dir, "benchmark")
            mkpath(sub)
            write(joinpath(sub, "Project.toml"), "[deps]\n")
            Workbench.ensure_sources!(sub, pkg.name, pkg.uuid)
            sub_data = TOML.parsefile(joinpath(sub, "Project.toml"))
            @test sub_data["deps"][pkg.name] == pkg.uuid
            @test sub_data["sources"][pkg.name]["path"] == ".."

            # parent_info — valid
            pname, puuid = Workbench.parent_info(dir)
            @test pname == pkg.name
            @test puuid == pkg.uuid
        end
    end

    @testset "parent_info errors" begin
        # Missing Project.toml
        mktempdir() do dir
            @test_throws Workbench.WorkbenchError Workbench.parent_info(dir)
        end

        # Project.toml without name/uuid
        mktempdir() do dir
            write(joinpath(dir, "Project.toml"), "[deps]\n")
            e = try Workbench.parent_info(dir); nothing catch e; e end
            @test e isa Workbench.WorkbenchError
            @test contains(e.msg, "missing required fields")
        end
    end

    @testset "malformed TOML" begin
        mktempdir() do dir
            write(joinpath(dir, "Project.toml"), "name = \"Bad\"\n[[[[invalid\n")
            e = try Workbench._safe_parsefile(joinpath(dir, "Project.toml")); nothing catch e; e end
            @test e isa Workbench.WorkbenchError
            @test contains(e.msg, "Failed to parse")
        end
    end

    # ── Deps errors ──────────────────────────────────────────────────────
    @testset "add/rm argument errors" begin
        mktempdir() do dir
            make_fake_pkg(dir)

            # No packages specified
            @test_throws ArgumentError Workbench.add(:dev; root=dir)
            @test_throws ArgumentError Workbench.rm(:dev; root=dir)

            # Sub-project doesn't exist
            @test_throws Workbench.WorkbenchError Workbench.add(:dev, "Foo"; root=dir)
            @test_throws Workbench.WorkbenchError Workbench.rm(:dev, "Foo"; root=dir)

            # Directory exists but no Project.toml
            mkpath(joinpath(dir, "dev"))
            @test_throws Workbench.WorkbenchError Workbench.add(:dev, "Foo"; root=dir)
        end
    end

    # ── Activate / Deactivate ────────────────────────────────────────────
    @testset "activate / deactivate" begin
        mktempdir() do dir
            pkg = make_fake_pkg(dir)

            # Set up a dev sub-project manually (no Pkg.resolve needed)
            dev_dir = joinpath(dir, "dev")
            mkpath(dev_dir)
            write(joinpath(dev_dir, "Project.toml"), """
                [deps]
                $(pkg.name) = "$(pkg.uuid)"

                [sources]
                $(pkg.name) = {path = ".."}
                """)

            # No startup.jl — just test LOAD_PATH stacking
            old_loadpath = copy(LOAD_PATH)

            Workbench.activate(:dev; root=dir)
            @test haskey(Workbench._ACTIVATED, :dev)
            dev_abs = abspath(dev_dir)
            @test dev_abs in LOAD_PATH

            # Idempotent
            Workbench.activate(:dev; root=dir)
            @test count(==(dev_abs), LOAD_PATH) == 1

            # Deactivate specific
            Workbench.deactivate(:dev)
            @test !haskey(Workbench._ACTIVATED, :dev)
            @test dev_abs ∉ LOAD_PATH

            # Deactivate all
            Workbench.activate(:dev; root=dir)
            Workbench.deactivate()
            @test isempty(Workbench._ACTIVATED)
            @test dev_abs ∉ LOAD_PATH

            # Restore LOAD_PATH
            empty!(LOAD_PATH)
            append!(LOAD_PATH, old_loadpath)
        end
    end

    @testset "activate with startup.jl" begin
        mktempdir() do dir
            pkg = make_fake_pkg(dir)
            dev_dir = joinpath(dir, "dev")
            mkpath(dev_dir)
            write(joinpath(dev_dir, "Project.toml"), """
                [deps]
                $(pkg.name) = "$(pkg.uuid)"

                [sources]
                $(pkg.name) = {path = ".."}
                """)

            # Write a startup.jl that creates a marker file
            marker = joinpath(dir, "startup_ran.marker")
            write(joinpath(dev_dir, "startup.jl"), """
                touch("$(escape_string(marker))")
                """)

            old_loadpath = copy(LOAD_PATH)

            Workbench.activate(:dev; root=dir)
            @test isfile(marker)

            Workbench.deactivate()
            empty!(LOAD_PATH)
            append!(LOAD_PATH, old_loadpath)
        end
    end

    @testset "activate force re-runs startup.jl" begin
        mktempdir() do dir
            pkg = make_fake_pkg(dir)
            dev_dir = joinpath(dir, "dev")
            mkpath(dev_dir)
            write(joinpath(dev_dir, "Project.toml"), """
                [deps]
                $(pkg.name) = "$(pkg.uuid)"

                [sources]
                $(pkg.name) = {path = ".."}
                """)

            counter_file = joinpath(dir, "counter.txt")
            write(joinpath(dev_dir, "startup.jl"), """
                n = isfile("$(escape_string(counter_file))") ? parse(Int, read("$(escape_string(counter_file))", String)) : 0
                write("$(escape_string(counter_file))", string(n + 1))
                """)

            old_loadpath = copy(LOAD_PATH)

            Workbench.activate(:dev; root=dir)
            @test read(counter_file, String) == "1"
            dev_abs = abspath(dev_dir)

            # Without force: already activated, startup.jl not re-run
            Workbench.activate(:dev; root=dir)
            @test read(counter_file, String) == "1"
            @test count(==(dev_abs), LOAD_PATH) == 1

            # With force: startup.jl re-runs, no duplicate LOAD_PATH entry
            Workbench.activate(:dev; root=dir, force=true)
            @test read(counter_file, String) == "2"
            @test count(==(dev_abs), LOAD_PATH) == 1

            Workbench.deactivate()
            empty!(LOAD_PATH)
            append!(LOAD_PATH, old_loadpath)
        end
    end

    @testset "activate quiet mode" begin
        # quiet=true without root: should not throw even outside a package dir
        mktempdir() do dir
            result = Workbench.activate(:dev; quiet=true)
            # This may or may not return nothing depending on pwd(), but must not throw
        end

        # quiet=true with explicit root that has no dev/
        mktempdir() do dir
            make_fake_pkg(dir)
            result = Workbench.activate(:dev; root=dir, quiet=true)
            @test result === nothing
            @test !haskey(Workbench._ACTIVATED, :dev)
        end

        # quiet=false with missing sub-project: throws WorkbenchError
        mktempdir() do dir
            make_fake_pkg(dir)
            @test_throws Workbench.WorkbenchError Workbench.activate(:dev; root=dir)
        end
    end

    @testset "activate errors" begin
        # Missing sub-project directory
        mktempdir() do dir
            make_fake_pkg(dir)
            @test_throws Workbench.WorkbenchError Workbench.activate(:dev; root=dir)
        end

        # Directory exists but no Project.toml
        mktempdir() do dir
            make_fake_pkg(dir)
            mkpath(joinpath(dir, "dev"))
            @test_throws Workbench.WorkbenchError Workbench.activate(:dev; root=dir)
        end
    end

    # ── Run errors ───────────────────────────────────────────────────────
    @testset "run errors" begin
        mktempdir() do dir
            make_fake_pkg(dir)

            # Missing sub-project
            @test_throws Workbench.WorkbenchError Workbench.run(:benchmark; root=dir)

            # Directory exists but no entry point
            mkpath(joinpath(dir, "benchmark"))
            write(joinpath(dir, "benchmark", "Project.toml"), "[deps]\n")
            @test_throws Workbench.WorkbenchError Workbench.run(:benchmark; root=dir)
        end
    end

    @testset "example errors" begin
        mktempdir() do dir
            make_fake_pkg(dir)

            # No examples/ directory
            @test_throws Workbench.WorkbenchError Workbench.example("foo"; root=dir)

            # examples/ exists but script missing
            mkpath(joinpath(dir, "examples"))
            @test_throws Workbench.WorkbenchError Workbench.example("foo"; root=dir)
        end
    end

    # ── Status ───────────────────────────────────────────────────────────
    @testset "status" begin
        mktempdir() do dir
            pkg = make_fake_pkg(dir)

            # Empty — should not error
            buf = IOBuffer()
            Workbench.status(; root=dir, io=buf)
            output = String(take!(buf))
            @test contains(output, pkg.name)
            @test contains(output, "No sub-projects")

            # With some sub-projects
            test_dir = joinpath(dir, "test")
            mkpath(test_dir)
            write(joinpath(test_dir, "runtests.jl"), "using Test\n")

            buf = IOBuffer()
            Workbench.status(; root=dir, io=buf)
            output = String(take!(buf))
            @test contains(output, ":test")
        end
    end

    @testset "status warnings" begin
        mktempdir() do dir
            pkg = make_fake_pkg(dir)

            # Sub-project with Project.toml but not in workspace
            test_dir = joinpath(dir, "test")
            mkpath(test_dir)
            write(joinpath(test_dir, "Project.toml"), "[deps]\n")
            write(joinpath(test_dir, "runtests.jl"), "using Test\n")

            buf = IOBuffer()
            Workbench.status(; root=dir, io=buf)
            output = String(take!(buf))
            @test contains(output, "⚠")
            @test contains(output, "not in [workspace]")

            # Orphaned workspace member (registered but directory missing)
            root_toml = TOML.parsefile(joinpath(dir, "Project.toml"))
            root_toml["workspace"] = Dict("projects" => ["test", "phantom"])
            open(joinpath(dir, "Project.toml"), "w") do io
                TOML.print(io, root_toml)
            end

            buf = IOBuffer()
            Workbench.status(; root=dir, io=buf)
            output = String(take!(buf))
            @test contains(output, "phantom")
            @test contains(output, "directory not found")
        end
    end
end
