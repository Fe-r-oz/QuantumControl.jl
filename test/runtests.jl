using QuantumControl
using QuantumPropagators
using IOCapture
using Test
using SafeTestsets

@testset "QuantumControl versions" begin
    captured = IOCapture.capture() do
        QuantumControl.print_versions()
    end
    println(captured.output)
    @test occursin("QuantumControlBase", captured.output)
    @test occursin("Krotov", captured.output)
    qp_exports = QuantumControl._exported_names(QuantumPropagators)
    @test :propagate ∈ qp_exports
    @test :QuantumControl ∉ qp_exports
end

# Note: comment outer @testset to stop after first @safetestset failure
@time @testset verbose = true "QuantumControl" begin


    print("\n* Functionals (test_functionals.jl):")
    @time @safetestset "Functionals" begin
        include("test_functionals.jl")
    end

    print("\n")

end;
