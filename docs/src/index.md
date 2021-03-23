# PackageAnalyzer.jl

The main functionality of the package is the [`analyze`](@ref) function:

```julia
julia> using PackageAnalyzer

julia> analyze("Flux")
Package Flux:
  * repo: https://github.com/FluxML/Flux.jl.git
  * uuid: 587475ba-b771-5e3f-ad9e-33799f191a9c
  * is reachable: true
  * lines of Julia code in `src`: 5074
  * lines of Julia code in `test`: 2167
  * has license(s) in file: MIT
    * filename: LICENSE.md
    * OSI approved: true
  * number of contributors: 151
  * has documentation: true
  * has tests: true
  * has continuous integration: true
    * GitHub Actions
    * Buildkite

```

The argument is a string pointing towards a local path or the name of
a package in a locally-installed registry (the General registry is checked by default).

*NOTE*: the Git repository of the package will be cloned, in order to inspect
its content.

You can also pass a [`RegistryEntry`](@ref), a simple datastructure which points
to the directory of the package in the registry, where the file `Package.toml`
is stored.  The function [`find_package`](@ref) gives you the
[`RegistryEntry`](@ref) of a package in your local copy of any registry, by
default the [General registry](https://github.com/JuliaRegistries/General).
`find_package` is invoked automatically when you pass the name of a package.

```julia
julia> analyze(find_package("JuMP"))
Package JuMP:
  * repo: https://github.com/jump-dev/JuMP.jl.git
  * uuid: 4076af6c-e467-56ae-b986-b466b2749572
  * is reachable: true
  * lines of Julia code in `src`: 15551
  * lines of Julia code in `test`: 10523
  * has license(s) in file: MPL-2.0
    * filename: LICENSE.md
    * OSI approved: true
  * number of contributors: 96
  * has documentation: true
  * has tests: true
  * has continuous integration: true
    * GitHub Actions
```

Additionally, you can pass in the module itself:

```julia
julia> using PackageAnalyzer

julia> analyze(PackageAnalyzer)
Package PackageAnalyzer:
  * repo:
  * uuid: e713c705-17e4-4cec-abe0-95bf5bf3e10c
  * is reachable: true
  * lines of Julia code in `src`: 481
  * lines of Julia code in `test`: 97
  * has license(s) in file: MIT
    * filename: LICENSE
    * OSI approved: true
  * has documentation: true
  * has tests: true
  * has continuous integration: true
    * GitHub Actions
```

You use the inplace version [`analyze!`](@ref), e.g. as `analyze!(root, find_package("Flux"))` to clone
the package to a particular directory `root` which is not cleaned up afterwards, and likewise can pass a vector of paths instead of a single path employ use a threaded loop to analyze each package.

You can also directly analyze the source code of a package via [`analyze`](@ref)
by passing in the path to it, for example with the `pkgdir` function:

```julia
julia> using PackageAnalyzer, DataFrames

julia> analyze(pkgdir(DataFrames))
Package DataFrames:
  * repo:
  * uuid: a93c6f00-e57d-5684-b7b6-d8193f3e46c0
  * is reachable: true
  * lines of Julia code in `src`: 15347
  * lines of Julia code in `test`: 15654
  * has license(s) in file: MIT
    * filename: LICENSE.md
    * OSI approved: true
  * has documentation: true
  * has tests: true
  * has continuous integration: true
    * GitHub Actions
```

## The `Package` struct

The returned values from [`analyze`](@ref), and [`analyze!`](@ref) are objects of the type `Package`, which has the following fields:

```julia
struct Package
    name::String # name of the package
    uuid::UUID # uuid of the package
    repo::String # URL of the repository
    subdir::String # subdirectory of the package in the repo
    reachable::Bool # can the repository be cloned?
    docs::Bool # does it have documentation?
    runtests::Bool # does it have the test/runtests.jl file?
    github_actions::Bool # does it use GitHub Actions?
    travis::Bool # does it use Travis CI?
    appveyor::Bool # does it use AppVeyor?
    cirrus::Bool # does it use Cirrus CI?
    circle::Bool # does it use Circle CI?
    drone::Bool # does it use Drone CI?
    buildkite::Bool # does it use Buildkite?
    azure_pipelines::Bool # does it use Azure Pipelines?
    gitlab_pipeline::Bool # does it use Gitlab Pipeline?
    license_files::Vector{@NamedTuple{license_filename::String, licenses_found::Vector{String}, license_file_percent_covered::Float64}} # a table of all possible license files
    licenses_in_project::Vector{String} # any licenses in the `license` key of the Project.toml
    lines_of_code::Vector{@NamedTuple{directory::String, language::Symbol, sublanguage::Union{Nothing, Symbol}, files::Int, code::Int, comments::Int, blanks::Int}} # table of lines of code
    contributors::Dict{String,Int} # Dictionary contributors => contributions
end
```


## Analyzing multiple packages

To run the analysis for multiple packages you can either use broadcasting
```julia
analyze.(registry_entries)
```
or use the method `analyze(registry_entries::AbstractVector{<:RegistryEntry})` which
runs the analysis with multiple threads.

You can use the function [`find_packages`](@ref) to find all packages in a given
registry:

```julia
julia> find_packages(; registry=general_registry())
4632-element Vector{PackageAnalyzer.RegistryEntry}:
 PackageAnalyzer.RegistryEntry("/Users/eph/.julia/registries/General/C/CitableImage")
 PackageAnalyzer.RegistryEntry("/Users/eph/.julia/registries/General/T/Trixi2Img")
 PackageAnalyzer.RegistryEntry("/Users/eph/.julia/registries/General/I/ImPlot")
 PackageAnalyzer.RegistryEntry("/Users/eph/.julia/registries/General/S/StableDQMC")
 PackageAnalyzer.RegistryEntry("/Users/eph/.julia/registries/General/S/Strapping")
[...]
```
Do not abuse this function! Consider using the in-place function `analyze!(root, registry_entries)` to avoid re-cloning packages if you might run the analysis more than once.

!!! warning
    Cloning all the repos in General will take more than 20 GB of disk space and can take up to a few hours to complete.

## License information

The `license_files` field of the `Package` object is a [`Tables.jl`](https://github.com/JuliaData/Tables.jl) row table
containing much more detailed information about any or all files containing
licenses, identified by [`licensecheck`](https://github.com/google/licensecheck) via [LicenseCheck.jl](https://github.com/ericphanson/LicenseCheck.jl). For example, [RandomProjectionTree.jl](https://github.com/jean-pierreBoth/RandomProjectionTree.jl) is dual licensed under both Apache-2.0 and the MIT license, and provides two separate license files. Interestingly, the README is also identified as containing an Apache-2.0 license; I've filed an [issue](https://github.com/google/licensecheck/issues/40) to see if this is intentional.

```julia
julia> using PackageAnalyzer, DataFrames

julia> result = analyze("RandomProjectionTree");

julia> DataFrame(result.license_files)
3×3 DataFrame
 Row │ license_filename  licenses_found  license_file_percent_covered
     │ String            Vector{String}  Float64
─────┼────────────────────────────────────────────────────────────────
   1 │ LICENSE-APACHE    ["Apache-2.0"]                     100.0
   2 │ LICENSE-MIT       ["MIT"]                            100.0
   3 │ README.md         ["Apache-2.0"]                       6.34921
```

Most packages contain a single file containing a license, and so have a single entry in the table.

## Lines of code

The `lines_of_code` field of the `Package` object is a Tables.jl row table
containing much more detailed information about the lines of code count
(thanks to `tokei`) and can e.g. be passed to a `DataFrame` for further analysis.

```julia
julia> using PackageAnalyzer, DataFrames

julia> result = analyze(pkgdir(DataFrames));

julia> DataFrame(result.lines_of_code)
13×7 DataFrame
 Row │ directory        language  sublanguage  files  code   comments  blanks
     │ String           Symbol    Union…       Int64  Int64  Int64     Int64
─────┼────────────────────────────────────────────────────────────────────────
   1 │ test             Julia                     27  15654       320    2109
   2 │ src              Julia                     28  15347       794    1009
   3 │ docs             Julia                      1     41         7       5
   4 │ docs             TOML                       1      4         0       2
   5 │ docs             Markdown                  14      0      3292     620
   6 │ docs             Markdown  Julia            3     29         3       4
   7 │ docs             Markdown  Python           1     13         0       1
   8 │ docs             Markdown  R                1      2         0       0
   9 │ Project.toml     TOML                       1     48         0       4
  10 │ CONTRIBUTING.md  Markdown                   1      0        56       8
  11 │ NEWS.md          Markdown                   1      0       112      10
  12 │ LICENSE.md       Markdown                   1      0        22       1
  13 │ README.md        Markdown                   1      0        21      10
```

## Contributors to the repository

If the package repository is hosted on GitHub and you can use [GitHub
authentication](@ref), the list of contributors is added to the `contributors`
field of the `Package` object.  This is a dictionary whose keys are the GitHub
usernames of the contributors, and the values are the corresponding numbers of
contributions in that repository.

```julia
julia> using PackageAnalyzer, DataFrames

julia> result = analyze("DataFrames");

julia> users = collect(keys(result.contributors));

julia> df = DataFrame(:User => users, :Contributions => map(x -> result.contributors[x], users));

julia> sort!(df, [:Contributions, :User], rev=true)
165×2 DataFrame
 Row │ User               Contributions
     │ String             Int64
─────┼──────────────────────────────────
   1 │ johnmyleswhite               431
   2 │ bkamins                      364
   3 │ powerdistribution            232
   4 │ nalimilan                    220
   5 │ garborg                      173
   6 │ quinnj                       101
   7 │ simonster                     87
   8 │ cjprybol                      50
   9 │ alyst                         48
  10 │ dmbates                       47
  11 │ tshort                        39
  12 │ doobwa                        32
  13 │ HarlanH                       32
  14 │ kmsquire                      30
  15 │ pdeffebach                    19
  16 │ ararslan                      19
  ⋮  │         ⋮                ⋮
```

## GitHub authentication

If you have a [GitHub Personal Access
Token](https://docs.github.com/en/github/authenticating-to-github/creating-a-personal-access-token),
you can obtain some extra information about packages whose repository is hosted
on GitHub (e.g. the list of contributors).  If you store the token as an
environment variable called `GITHUB_TOKEN` or `GITHUB_AUTH`, this will be
automatically used whenever possible, otherwise you can generate a GitHub
authentication with the [`PackageAnalyzer.github_auth`](@ref) function and pass
it to the functions accepting the `auth::GitHub.Authorization` keyword argument.
