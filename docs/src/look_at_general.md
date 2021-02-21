# A look at the General registry

First, let's load in the data.
```@example 1
using Arrow, AnalyzeRegistry, DataFrames
Arrow.ArrowTypes.registertype!(AnalyzeRegistry.Package, AnalyzeRegistry.Package)

# https://github.com/JuliaData/Arrow.jl/issues/132
Arrow.ArrowTypes.JULIA_TO_ARROW_TYPE_MAPPING[Nothing] = ("JuliaLang.Nothing", Nothing)
Arrow.ArrowTypes.ARROW_TO_JULIA_TYPE_MAPPING["JuliaLang.Nothing"] = (Nothing, Nothing)

load(path) = copy(Arrow.Table(path).packages)

results = load("assets/all_pkgs_results.arrow")

# https://discourse.julialang.org/t/slowness-of-fieldnames-and-properynames/55364/2
@generated function named_tuple(obj::T) where {T}
    NT = NamedTuple{fieldnames(obj), Tuple{fieldtypes(obj)...}}
    return :($NT(tuple($((:(getfield(obj, $i)) for i in 1:fieldcount(obj))...))))
end

df = DataFrame(named_tuple.(results))
sort!(df, :name)
df[1:5, Not([:uuid, :lines_of_code, :license_files])]
```

Here, we see some information about presence of docs, tests, and CI, for the first five packages (alphabetically). We omit the `lines_of_code` and `license_files` fields, since these are tables of their own that we'll look at next.

## Lines of code

Let us assemble all of the `lines_of_code` tables into their own DataFrame.

```@example 1
loc_df = DataFrame()
for pkg in results
    pkg_df = DataFrame(pkg.lines_of_code)
    insertcols!(pkg_df, 1, :name => fill(pkg.name, nrow(pkg_df)))
    append!(loc_df, pkg_df)
end
sort!(loc_df, :code; rev=true)
loc_df[1:10, :]
```
We can see the largest entries by lines of code seem to be mostly generated code, like plots or HTML. Let's look at just at Julia language code in the `src` directory (with no `sublanguage`, i.e. it's not another language embedded inside Julia):

```@example 1
grps = groupby(loc_df, [:directory, :language, :sublanguage])
src_code = DataFrame(grps[(; directory="src", language=:Julia, sublanguage=nothing)])
sort!(src_code, :code; rev=true)
src_code[1:20, Not([:sublanguage])]
```

```@example 1
sum(src_code.code)
```

We see there are almost 7 million lines of Julia source code in General!

```@example 1
using GRUtils
histogram(src_code.code, xlog=true, xlabel="Lines of Julia source code",
          ylabel="Number of packages")
savefig("loc_hist.svg") # hide
```

![](loc_hist.svg)

With a logarithmic x-axis, we see a nice unimodal distribution, centered around ~500 lines of code:

```@example 1
using StatsBase
summarystats(src_code.code)
```

We can also generate a wordcloud with the names of the 500 largest packages:

```julia
using WordCloud
src_wc = generate!(wordcloud(src_code.name[1:500], src_code.code[1:500]))
paint(src_wc, "assets/src_wc.svg")
```

![Word cloud](assets/src_wc.svg)


In the package folder, where does Julia code live?


```@example 1
dir_grps = groupby(filter(:language => isequal(:Julia), loc_df), :directory)
dir_df = sort!(combine(dir_grps, :code => sum => :loc), :loc; rev=true)
n_bars=6
heights = [dir_df.loc[1:(n_bars-1)]; sum(dir_df.loc[n_bars+1:end])]
labels = [dir_df.directory[1:(n_bars-1)]; "other"]
barplot(labels, heights; ylabel="Total lines of Julia code", xlabel="Top-level directory")
annotations(1:length(heights), heights .+ 0.03 * maximum(heights) , string.(heights), halign="center")
xticks(1)
savefig("dir_bar.svg") # hide
```

![](dir_bar.svg)

Mostly in `src`, as expected! What's the most common non-Julia code in `src`?

```@example 1
grps = groupby(filter([:directory, :language] => ((d, l) -> d == "src" && l !== :Julia), loc_df), :language)

sort!(combine(grps, :code => sum, [:name, :code] => ((n, c) -> n[argmax(c)]) => :biggest_contributer, :code => maximum => :biggest_contribution), :code_sum; rev=true)[1:10, :]
```

We see code from a variety of different languages can live in `src`, but often most of the lines come from a single package. Note the "Invalid Project.toml"; this likely means the package in question does not have a Project.toml at all (and instead still has the old Requires file).

We could continue exploring this all day, but instead we suggest you download the data and do some digging yourself!

## Licenses

```@example 1
license_df = DataFrame()
for pkg in results
    pkg_df = DataFrame(pkg.license_files)
    insertcols!(pkg_df, 1, :name => fill(pkg.name, nrow(pkg_df)))
    append!(license_df, pkg_df)
end
sort!(license_df, :licenses_found; by=length, rev=true)
license_df[1:10, :]
```
