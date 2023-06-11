# PackageAnalyzer.jl

The main functionality of the package is the [`analyze`](@ref) function:

```julia
julia> using PackageAnalyzer

julia> analyze("Flux")
PackageV1 Flux:
  * repo: https://github.com/FluxML/Flux.jl.git
  * uuid: 587475ba-b771-5e3f-ad9e-33799f191a9c
  * version: 0.13.6
  * is reachable: true
  * tree hash: 76ca02c7c0cb7b8337f7d2d0eadb46ed03c1e843
  * Julia code in `src`: 5299 lines
  * Julia code in `test`: 3030 lines (36.4% of `test` + `src`)
  * documentation in `docs`: 1856 lines (25.9% of `docs` + `src`)
  * documentation in README: 14 lines
  * has license(s) in file: MIT
    * filename: LICENSE.md
    * OSI approved: true
  * has `docs/make.jl`: true
  * has `test/runtests.jl`: true
  * has continuous integration: true
    * GitHub Actions
    * Buildkite
```

The argument is a string, which can be the name of a package, a local path or a URL.

*NOTE*: the Git repository of the package may be cloned, in order to inspect
its content.

You can also pass the output of [`find_package`](@ref) which is used under-the-hood
to look up package names in any installed registries. `find_package` also allows one to specify
a package by `UUID`.

```julia
julia> analyze(find_package("JuMP"; version=v"1"))
PackageV1 JuMP:
  * repo: https://github.com/jump-dev/JuMP.jl.git
  * uuid: 4076af6c-e467-56ae-b986-b466b2749572
  * version: 1.0.0
  * is reachable: true
  * tree hash: 936e7ebf6c84f0c0202b83bb22461f4ebc5c9969
  * Julia code in `src`: 16906 lines
  * Julia code in `test`: 12777 lines (43.0% of `test` + `src`)
  * documentation in `docs`: 15978 lines (48.6% of `docs` + `src`)
  * documentation in README: 79 lines
  * has license(s) in file: MPL-2.0
    * filename: LICENSE.md
    * OSI approved: true
  * has `docs/make.jl`: true
  * has `test/runtests.jl`: true
  * has continuous integration: true
    * GitHub Actions
```

Additionally, you can pass in the module itself:

```julia
julia> using PackageAnalyzer

julia> analyze(PackageAnalyzer)
PackageV1 PackageAnalyzer:
  * repo:
  * uuid: e713c705-17e4-4cec-abe0-95bf5bf3e10c
  * version: nothing
  * is reachable: true
  * tree hash: 7bfd2ab7049d92809eb18eed1b0548c7e07ec150
  * Julia code in `src`: 912 lines
  * Julia code in `test`: 276 lines (23.2% of `test` + `src`)
  * documentation in `docs`: 263 lines (22.4% of `docs` + `src`)
  * documentation in README: 44 lines
  * has license(s) in file: MIT
    * filename: LICENSE
    * OSI approved: true
  * has `docs/make.jl`: true
  * has `test/runtests.jl`: true
  * has continuous integration: true
    * GitHub Actions
```

You can also directly analyze the source code of a package via [`analyze`](@ref)
by passing in the path to it, for example with the `pkgdir` function:

```julia
julia> using PackageAnalyzer, DataFrames

julia> analyze(pkgdir(DataFrames))
PackageV1 DataFrames:
  * repo:
  * uuid: a93c6f00-e57d-5684-b7b6-d8193f3e46c0
  * version: 0.0.0
  * is reachable: true
  * tree hash: db2a9cb664fcea7836da4b414c3278d71dd602d2
  * Julia code in `src`: 15628 lines
  * Julia code in `test`: 21089 lines (57.4% of `test` + `src`)
  * documentation in `docs`: 6270 lines (28.6% of `docs` + `src`)
  * documentation in README: 21 lines
  * has license(s) in file: MIT
    * filename: LICENSE.md
    * OSI approved: true
  * has `docs/make.jl`: true
  * has `test/runtests.jl`: true
  * has continuous integration: true
    * GitHub Actions
```

You can pass the keyword argument `root` to specify a directory to store downloaded code.

## The `PackageV1` struct

The returned values from [`analyze`](@ref), and [`analyze!`](@ref) are objects of the type `PackageV1`, which has the following fields:

```julia
struct PackageV1
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
    license_files::Vector{LicenseV1}} # a table of all possible license files
    licenses_in_project::Vector{String} # any licenses in the `license` key of the Project.toml
    lines_of_code::Vector{LinesOfCodeV1} # table of lines of code
    contributors::Vector{ContributorsV1} # table of contributor data
    version::Union{String, Missing} # the version number, if a release was analyzed
    tree_hash::String # the tree hash of the code that was analyzed
end
```

where:
* `LicenseV1` contains fields `license_filename::String, licenses_found::Vector{String}, license_file_percent_covered::Float64`,
* `LinesOfCodeV1` contains fields `directory::String, language::Symbol, sublanguage::Union{Nothing, Symbol}, files::Int, code::Int, comments::Int, blanks::Int`,
* and `ContributorsV1` contains fields `login::Union{String,Missing}, id::Union{Int,Missing}, name::Union{String,Missing}, type::String, contributions::Int`.


Adding additional fields to `PackageV1` is *not* considered breaking, and may occur in feature releases of PackageAnalyzer.jl.

Removing or altering the meaning of existing fields *is* considered breaking and will only occur in major releases of PackageAnalyzer.jl.


## Analyzing multiple packages

To run the analysis for multiple packages you can either use broadcasting
```julia
analyze.(pkg_entries)
```
or use the function `analyze_packages(pkg_entries)` which
runs the analysis with multiple threads. Here, `pkg_entries` may be any valid input to `analyze`.

You can use the function [`find_packages`](@ref) to find all packages in a given
registry:

```julia
julia> result = find_packages(; registry=general_registry());

julia> summary(result)
"7213-element Vector{PkgSource}"
```

Do not abuse this function!

!!! warning
    Cloning all the repos in General will take more than 20 GB of disk space and can take up to a few hours to complete.


You can also use `find_packages_in_manifest` to use a Manifest.toml to lookup
packages and their versions. Besides handling release dependencies, this should also correctly handle
dev'd dependencies, and non-released `Pkg.add`'d dependencies. The helper `analyze_manifest` is provided
as a convenience to composing `find_packages_in_manifest` and `analyze_packages`.

## License information

The `license_files` field of the `PackageV1` object is a [`Tables.jl`](https://github.com/JuliaData/Tables.jl) row table
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

The `lines_of_code` field of the `PackageV1` object is a Tables.jl row table
containing much more detailed information about the lines of code count
(thanks to `tokei`) and can e.g. be passed to a `DataFrame` for further analysis.

```julia
julia> using PackageAnalyzer, DataFrames

julia> result = analyze(pkgdir(DataFrames));

julia> DataFrame(result.lines_of_code)
15×7 DataFrame
 Row │ directory        language  sublanguage  files  code   comments  blanks
     │ String           Symbol    Union…       Int64  Int64  Int64     Int64
─────┼────────────────────────────────────────────────────────────────────────
   1 │ test             Julia                     29  17512       359    2264
   2 │ src              Julia                     31  15809       885    1253
   3 │ benchmarks       Julia                      4    245        30      50
   4 │ benchmarks       Shell                      2     15         0       0
   5 │ docs             Julia                      1     45         6       5
   6 │ docs             TOML                       1     11         0       1
   7 │ docs             Markdown                  16      0      3782     662
   8 │ docs             Markdown  Julia            4     30         3       4
   9 │ docs             Markdown  Python           1     13         0       1
  10 │ docs             Markdown  R                1      6         0       0
  11 │ Project.toml     TOML                       1     51         0       4
  12 │ README.md        Markdown                   1      0        21      10
  13 │ NEWS.md          Markdown                   1      0       267      47
  14 │ LICENSE.md       Markdown                   1      0        22       1
  15 │ CONTRIBUTING.md  Markdown                   1      0       138      20
```

## Contributors to the repository

If the package repository is hosted on GitHub and you can use [GitHub
authentication](@ref), the list of contributors is added to the `contributors`
field of the `PackageV1` object.  This is a table which includes the GitHub username ("login") and
the GitHub ID ("id") for contributors identified as GitHub "users", and the "name" for contributors
identified as "Anonymous" contributors, as well as the number of contributions provided by that user to
the repository. This is the data returned from the GitHub API, and there may be people for which
some of their contributions are marked as from an anonymous user (possibly more than one!) and
some of their contributions are associated to their GitHub username.

```julia
julia> using PackageAnalyzer, DataFrames

julia> result = analyze("DataFrames");

julia> df = DataFrame(result.contributors);

julia> sort!(df, :contributions, rev=true)
189×5 DataFrame
 Row │ login                id        name           type       contributions
     │ String?              Int64?    String?        String     Int64
─────┼────────────────────────────────────────────────────────────────────────
   1 │ johnmyleswhite          22064  missing        User                 431
   2 │ bkamins               6187170  missing        User                 412
   3 │ powerdistribution     5247292  missing        User                 232
   4 │ nalimilan             1120448  missing        User                 223
   5 │ garborg               2823840  missing        User                 173
   6 │ quinnj                2896623  missing        User                 104
   7 │ simonster              470884  missing        User                  87
   8 │ missing               missing  Harlan Harris  Anonymous             67
   9 │ cjprybol              3497642  missing        User                  50
  10 │ alyst                  348591  missing        User                  48
  11 │ dmbates                371258  missing        User                  47
  12 │ tshort                 636420  missing        User                  39
  13 │ doobwa                  79467  missing        User                  32
  14 │ HarlanH                130809  missing        User                  32
  15 │ kmsquire               223250  missing        User                  30
  ⋮  │          ⋮              ⋮            ⋮            ⋮            ⋮
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
