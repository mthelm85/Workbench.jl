using Workbench
using Test
using Aqua
using JET

@testset "Workbench.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(Workbench)
    end
    @testset "Code linting (JET.jl)" begin
        JET.test_package(Workbench; target_defined_modules = true)
    end
    # Write your tests here.
end
