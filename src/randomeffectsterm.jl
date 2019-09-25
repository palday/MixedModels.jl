struct RandomEffectsTerm <: AbstractTerm
    lhs::StatsModels.TermOrTerms
    rhs::StatsModels.TermOrTerms
    function RandomEffectsTerm(lhs,rhs)
        if isempty(intersect(StatsModels.termvars(lhs), StatsModels.termvars(rhs)))
            # when the minimum Julia version is increased to 1.2, we can change
            # this to the more generic !hasproperty(rhs,:contrasts)
            # which actually tests the property we care about
            if !isa(rhs, CategoricalTerm)
                throw(ArgumentError("blocking variables (those behind |) must be Categorical ($(rhs) is not)"))
            end
            new(lhs, rhs)
        else
            throw(ArgumentError("Same variable appears on both sides of |"))
        end
    end
end

function RandomEffectsTerm(lhs, rhs::FunctionTerm{typeof(/)})
    RandomEffectsTerm(lhs, rhs.args_parsed[1]) +
        RandomEffectsTerm(lhs, rhs.args_parsed[1] & rhs.args_parsed[2])
end

Base.show(io::IO, t::RandomEffectsTerm) = print(io, "($(t.lhs) | $(t.rhs))")
StatsModels.is_matrix_term(::Type{RandomEffectsTerm}) = false

function StatsModels.termvars(t::RandomEffectsTerm)
    vcat(StatsModels.termvars(t.lhs), StatsModels.termvars(t.rhs))
end

# this is too generic and it's type piracy
function StatsModels.collect_matrix_terms(tt::Tuple)
    nonnested = [t for t in tt if t isa AbstractTerm]
    nested = [t for t in tt if t isa Tuple{RandomEffectsTerm, RandomEffectsTerm}]

    if length(nested) + length(nonnested) != length(tt)
        throw(ArgumentError("tuple should contain only Terms and tuples of RandomEffectTerms"))
    end

    terms = copy(nonnested)
    for rt in nested
        terms = append!(terms, rt)
    end

    StatsModels.collect_matrix_terms(Tuple(terms))
end

function StatsModels.collect_matrix_terms(tt::Tuple{AbstractTerm,Tuple{RandomEffectsTerm,RandomEffectsTerm}})
    StatsModels.collect_matrix_terms(Tuple(vcat(tt[1],tt[2][1],tt[2][2])))
end

function StatsModels.apply_schema(t::FunctionTerm{typeof(|)}, schema::StatsModels.FullRank,
        Mod::Type{<:MixedModel})
    lhs, rhs = apply_schema.(t.args_parsed, Ref(schema), Mod)
    RandomEffectsTerm(MatrixTerm(lhs), rhs)
end

function StatsModels.modelcols(t::RandomEffectsTerm, d::NamedTuple)
    lhs = t.lhs
    z = Matrix(transpose(modelcols(lhs, d)))
    cnames = coefnames(lhs)
    T = eltype(z)
    S = size(z, 1)
    grp = t.rhs
    m = reshape(1:abs2(S), (S, S))
    inds = sizehint!(Int[], (S * (S + 1)) >> 1)
    for j in 1:S, i in j:S
        push!(inds, m[i,j])
    end
    invindex = grp.contrasts.invindex
    refs = convert(Vector{Int32}, getindex.(Ref(invindex), d[grp.sym]))
    J = Int32.(1:length(refs))
    II = refs
    if S > 1
        J = repeat(J, inner=S)
        II = Int32.(vec([(r - 1)*S + j for j in 1:S, r in refs]))
    end
    ReMat{T,S}(grp, refs, isa(cnames, String) ? [cnames] : collect(cnames),
        z, z, LowerTriangular(Matrix{T}(I, S, S)), inds,
        sparse(II, J, vec(z)), Matrix{T}(undef, (S, length(invindex))))
end
