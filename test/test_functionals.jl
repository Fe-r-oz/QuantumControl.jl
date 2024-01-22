using Test
using LinearAlgebra
using QuantumControl: QuantumControl, Trajectory
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
PROBLEM = dummy_control_problem(;
    N=N_HILBERT,
    n_trajectories=N,
    n_controls=L,
    n_steps=N_T,
    rng=RNG
)


@testset "functionals-tau-no-tau" begin

    # Test that the various chi routines give the same result whether they are
    # called with ϕ states or with τ values

    trajectories = PROBLEM.trajectories
    χ1 = [similar(traj.initial_state) for traj in trajectories]
    χ2 = [similar(traj.initial_state) for traj in trajectories]
    ϕ = [random_state_vector(N_HILBERT; rng=RNG) for k = 1:N]
    τ = [traj.target_state ⋅ ϕ[k] for (k, traj) in enumerate(trajectories)]

    @test J_T_re(ϕ, trajectories) ≈ J_T_re(nothing, trajectories; τ)
    chi_re!(χ1, ϕ, trajectories)
    chi_re!(χ2, ϕ, trajectories; τ=τ)
    @test maximum(norm.(χ1 .- χ2)) < 1e-12

    @test J_T_sm(ϕ, trajectories) ≈ J_T_sm(nothing, trajectories; τ)
    chi_sm!(χ1, ϕ, trajectories)
    chi_sm!(χ2, ϕ, trajectories; τ=τ)
    @test maximum(norm.(χ1 .- χ2)) < 1e-12

    @test J_T_ss(ϕ, trajectories) ≈ J_T_ss(nothing, trajectories; τ)
    chi_ss!(χ1, ϕ, trajectories)
    chi_ss!(χ2, ϕ, trajectories; τ=τ)
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
    trajectories = [Trajectory(Ψ, nothing) for Ψ ∈ basis]
    @test J_T(ϕ, trajectories) ≈ J_T_C(CPHASE_lossy)

    chi_J_T! = make_chi(J_T, trajectories; mode=:automatic, automatic=Zygote)
    χ = [similar(traj.initial_state) for traj in trajectories]
    chi_J_T!(χ, ϕ, trajectories)

    J_T2 = gate_functional(J_T_C; w=0.1)
    @test (J_T2(ϕ, trajectories) - J_T_C(CPHASE_lossy)) < -0.1

    chi_J_T2! = make_chi(J_T2, trajectories; mode=:automatic, automatic=Zygote)
    χ2 = [similar(traj.initial_state) for traj in trajectories]
    chi_J_T2!(χ2, ϕ, trajectories)

    QuantumControl.set_default_ad_framework(nothing; quiet=true)

    capture = IOCapture.capture(rethrow=Union{}, passthrough=true) do
        make_gate_chi(J_T_C, trajectories)
    end
    @test capture.value isa ErrorException
    if capture.value isa ErrorException
        @test contains(capture.value.msg, "no default `automatic`")
    end

    QuantumControl.set_default_ad_framework(Zygote; quiet=true)
    capture = IOCapture.capture() do
        make_gate_chi(J_T_C, trajectories)
    end
    @test contains(capture.output, "automatic with Zygote")
    chi_J_T_C_zyg! = capture.value
    χ_zyg = [similar(traj.initial_state) for traj in trajectories]
    chi_J_T_C_zyg!(χ_zyg, ϕ, trajectories)

    QuantumControl.set_default_ad_framework(FiniteDifferences; quiet=true)
    capture = IOCapture.capture() do
        make_gate_chi(J_T_C, trajectories)
    end
    @test contains(capture.output, "automatic with FiniteDifferences")
    chi_J_T_C_fdm! = capture.value
    χ_fdm = [similar(traj.initial_state) for traj in trajectories]
    chi_J_T_C_fdm!(χ_fdm, ϕ, trajectories)

    @test maximum(norm.(χ_zyg .- χ)) < 1e-12
    @test maximum(norm.(χ_zyg .- χ_fdm)) < 1e-12

    QuantumControl.set_default_ad_framework(nothing; quiet=true)

    chi_J_T_C_zyg2! = make_gate_chi(J_T_C, trajectories; automatic=Zygote, w=0.1)
    χ_zyg2 = [similar(traj.initial_state) for traj in trajectories]
    chi_J_T_C_zyg2!(χ_zyg2, ϕ, trajectories)

    chi_J_T_C_fdm2! = make_gate_chi(J_T_C, trajectories; automatic=FiniteDifferences, w=0.1)
    χ_fdm2 = [similar(traj.initial_state) for traj in trajectories]
    chi_J_T_C_fdm2!(χ_fdm2, ϕ, trajectories)

    @test maximum(norm.(χ_zyg2 .- χ2)) < 1e-12
    @test maximum(norm.(χ_zyg2 .- χ_fdm2)) < 1e-12

end
