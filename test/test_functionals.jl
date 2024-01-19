using Test
using LinearAlgebra
using QuantumControl: QuantumControl, Objective
using QuantumControl.Functionals
using QuantumControl.Functionals: chi_re!, chi_sm!, chi_ss!
using QuantumControlTestUtils.RandomObjects: random_state_vector
using QuantumControlTestUtils.DummyOptimization: dummy_control_problem
using TwoQubitWeylChamber: D_PE, gate_concurrence, unitarity
using StableRNGs: StableRNG
using Zygote
using FiniteDifferences
using IOCapture

const 𝕚 = 1im
const ⊗ = kron

N_HILBERT = 10
N = 4
L = 2
N_T = 50
RNG = StableRNG(4290326946)
PROBLEM =
    dummy_control_problem(; N=N_HILBERT, n_objectives=N, n_controls=L, n_steps=N_T, rng=RNG)


@testset "functionals-tau-no-tau" begin

    # Test that the various chi routines give the same result whether they are
    # called with ϕ states or with τ values

    objectives = PROBLEM.objectives
    χ1 = [similar(obj.initial_state) for obj in objectives]
    χ2 = [similar(obj.initial_state) for obj in objectives]
    ϕ = [random_state_vector(N_HILBERT; rng=RNG) for k = 1:N]
    τ = [obj.target_state ⋅ ϕ[k] for (k, obj) in enumerate(objectives)]

    @test J_T_re(ϕ, objectives) ≈ J_T_re(nothing, objectives; τ)
    chi_re!(χ1, ϕ, objectives)
    chi_re!(χ2, ϕ, objectives; τ=τ)
    @test maximum(norm.(χ1 .- χ2)) < 1e-12

    @test J_T_sm(ϕ, objectives) ≈ J_T_sm(nothing, objectives; τ)
    chi_sm!(χ1, ϕ, objectives)
    chi_sm!(χ2, ϕ, objectives; τ=τ)
    @test maximum(norm.(χ1 .- χ2)) < 1e-12

    @test J_T_ss(ϕ, objectives) ≈ J_T_ss(nothing, objectives; τ)
    chi_ss!(χ1, ϕ, objectives)
    chi_ss!(χ2, ϕ, objectives; τ=τ)
    @test maximum(norm.(χ1 .- χ2)) < 1e-12

end


@testset "gate functional" begin

    CPHASE_lossy = [
        0.99  0    0    0
        0     0.99 0    0
        0     0    0.99 0
        0     0    0   0.99𝕚
    ]

    function ket(i::Int64; N=N)
        Ψ = zeros(ComplexF64, N)
        Ψ[i+1] = 1
        return Ψ
    end

    function ket(indices::Int64...; N=N)
        Ψ = ket(indices[1]; N=N)
        for i in indices[2:end]
            Ψ = Ψ ⊗ ket(i; N=N)
        end
        return Ψ
    end

    function ket(label::AbstractString; N=N)
        indices = [parse(Int64, digit) for digit in label]
        return ket(indices...; N=N)
    end

    basis = [ket("00"), ket("01"), ket("10"), ket("11")]


    J_T_C(U; w=0.5) = w * (1 - gate_concurrence(U)) + (1 - w) * (1 - unitarity(U))

    @test 0.6 < gate_concurrence(CPHASE_lossy) < 0.8
    @test 0.97 < unitarity(CPHASE_lossy) < 0.99
    @test 0.1 < J_T_C(CPHASE_lossy) < 0.2


    J_T = gate_functional(J_T_C)
    ϕ = transpose(CPHASE_lossy) * basis
    objectives = [Objective(; initial_state=Ψ, generator=nothing) for Ψ ∈ basis]
    @test J_T(ϕ, objectives) ≈ J_T_C(CPHASE_lossy)

    chi_J_T! = make_chi(J_T, objectives; mode=:automatic, automatic=Zygote)
    χ = [similar(obj.initial_state) for obj in objectives]
    chi_J_T!(χ, ϕ, objectives)

    J_T2 = gate_functional(J_T_C; w=0.1)
    @test (J_T2(ϕ, objectives) - J_T_C(CPHASE_lossy)) < -0.1

    chi_J_T2! = make_chi(J_T2, objectives; mode=:automatic, automatic=Zygote)
    χ2 = [similar(obj.initial_state) for obj in objectives]
    chi_J_T2!(χ2, ϕ, objectives)

    QuantumControl.set_default_ad_framework(nothing; quiet=true)

    capture = IOCapture.capture(rethrow=Union{}, passthrough=true) do
        make_gate_chi(J_T_C, objectives)
    end
    @test capture.value isa ErrorException
    if capture.value isa ErrorException
        @test contains(capture.value.msg, "no default `automatic`")
    end

    QuantumControl.set_default_ad_framework(Zygote; quiet=true)
    capture = IOCapture.capture() do
        make_gate_chi(J_T_C, objectives)
    end
    @test contains(capture.output, "automatic with Zygote")
    chi_J_T_C_zyg! = capture.value
    χ_zyg = [similar(obj.initial_state) for obj in objectives]
    chi_J_T_C_zyg!(χ_zyg, ϕ, objectives)

    QuantumControl.set_default_ad_framework(FiniteDifferences; quiet=true)
    capture = IOCapture.capture() do
        make_gate_chi(J_T_C, objectives)
    end
    @test contains(capture.output, "automatic with FiniteDifferences")
    chi_J_T_C_fdm! = capture.value
    χ_fdm = [similar(obj.initial_state) for obj in objectives]
    chi_J_T_C_fdm!(χ_fdm, ϕ, objectives)

    @test maximum(norm.(χ_zyg .- χ)) < 1e-12
    @test maximum(norm.(χ_zyg .- χ_fdm)) < 1e-12

    QuantumControl.set_default_ad_framework(nothing; quiet=true)

    chi_J_T_C_zyg2! = make_gate_chi(J_T_C, objectives; automatic=Zygote, w=0.1)
    χ_zyg2 = [similar(obj.initial_state) for obj in objectives]
    chi_J_T_C_zyg2!(χ_zyg2, ϕ, objectives)

    chi_J_T_C_fdm2! = make_gate_chi(J_T_C, objectives; automatic=FiniteDifferences, w=0.1)
    χ_fdm2 = [similar(obj.initial_state) for obj in objectives]
    chi_J_T_C_fdm2!(χ_fdm2, ϕ, objectives)

    @test maximum(norm.(χ_zyg2 .- χ2)) < 1e-12
    @test maximum(norm.(χ_zyg2 .- χ_fdm2)) < 1e-12

end
