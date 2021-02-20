# A look at the General registry

## Lines of Cod

```julia
using Arrow, AnalyzeRegistry, DataFrames
Arrow.ArrowTypes.registertype!(AnalyzeRegistry.Package, AnalyzeRegistry.Package)
Arrow.ArrowTypes.JULIA_TO_ARROW_TYPE_MAPPING[Nothing] = ("JuliaLang.Nothing", Nothing)
Arrow.ArrowTypes.ARROW_TO_JULIA_TYPE_MAPPING["JuliaLang.Nothing"] = (Nothing, Nothing)

# https://discourse.julialang.org/t/slowness-of-fieldnames-and-properynames/55364/2
@generated function named_tuple(obj::T) where {T}
    NT = NamedTuple{fieldnames(obj), Tuple{fieldtypes(obj)...}}
    return :($NT(tuple($((:(getfield(obj, $i)) for i in 1:fieldcount(obj))...))))
end

load(path) = copy(Arrow.Table(path).packages)
results = load("/Users/eph/iCloudDrive/all_pkgs_results.arrow")

df = DataFrame(named_tuple.(results))

eltype_names(::AbstractVector{<:NamedTuple{names}}) where {names} = names

function expand_subtable(df, col)
    @assert eltype(df[!, col]) <: AbstractVector{<:NamedTuple}
    df_flat = flatten(df, col)
    resulting_cols = collect(eltype_names(df_flat[!, col]))
    select!(df_flat, Not([col]), col => ByRow(values) => resulting_cols)
    return df_flat
end

df = expand_subtable(df, :lines_of_code)

using TableOperations

function df_with_constant_cols(tab, ps::Pair{<:Union{String,Symbol}}...)
    df = DataFrame(tab)
    for p in ps
        df[!, first(p)] = fill(last(p), nrow(df))
    end
    names = collect(first.(ps))
    select!(df, names, Not(names))
    return df
end

_join(tab_itr) = TableOperations.joinpartitions(Tables.partitioner(tab_itr))

df = DataFrame(_join( df_with_constant_cols(pkg.lines_of_code, :name => pkg.name) for pkg in results ))

grps = groupby(df, [:directory, :language, :sublanguage])
filt = grps[(; directory="src", language=:Julia, sublanguage=nothing)]

sum(filt.code)

sum_by_dir = sort!(combine(grps, :code => sum), :code_sum; rev=true)

map(tab -> sum(tab.code), grps)
```
