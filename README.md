# AnalyzeRegistry

Package to analyze the prevalence of documentation, testing and continuous
integration in Julia packages in a given registry.

## Installation

The package works on Julia v1.6 and following versions.  *NOTE*: the package
requires having [Git](https://git-scm.com/) installed and available in the
`PATH`.

To install the package, in Julia's REPL, press `]` to enter the Pkg mode and run
the command

```
add https://github.com/giordano/AnalyzeRegistry.jl
```

Alternatively, you can run

```julia
using Pkg
Pkg.add("https://github.com/giordano/AnalyzeRegistry.jl")
```

## Usage

The main functionality of the package is the `analyze` and `analyze_from_registry` functions:

```julia
julia> analyze_from_registry(joinpath(general_registry(), "F", "Flux"))
Package Flux:
  * repo: https://github.com/FluxML/Flux.jl.git
  * uuid: 587475ba-b771-5e3f-ad9e-33799f191a9c
  * is reachable: true
  * has documentation: true
  * has tests: true
  * has continuous integration: true
    * GitHub Actions
    * Buildkite
  * has license(s) in file: MIT
    * filename: LICENSE.md
    * OSI approved: true
  * lines of Julia code in `src`: 4863
  * lines of Julia code in `test`: 2034

```

The argument is the path to the directory of the package in the registry, where
the file `Package.toml` is stored.  The function `general_registry()` gives you
the path to the local copy of the [General
registry](https://github.com/JuliaRegistries/General).

*NOTE*: the Git repository of the package will be cloned, in order to inspect
its content.

The returned value is the struct `Package`, which has the following fields:
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
    license_filename::Union{Missing, String} # e.g. `LICENSE` or `COPYING`
    licenses_found::Vector{String} # all the licenses found in `license_filename`
    license_file_percent_covered::Union{Missing, Float64} # how much of the license file is covered by the licenses found
    licenses_in_project::Union{Missing,Vector{String}} # any licenses in the `license` key of the Project.toml
end
```

To run the analysis for multiple packages you can either use broadcasting
```julia
analyze_from_registry.(package_paths_in_registry)
```
or use the method `analyze_from_registry(package_paths_in_registry::AbstractVector{<:AbstractString})` which
leaverages [`FLoops.jl`](https://github.com/JuliaFolds/FLoops.jl) to run the
analysis with multiple threads.

You can use the function `find_packages` to find all packages in a given
registry:
```julia
julia> find_packages(general_registry())
4312-element Vector{String}:
 "/home/user/.julia/registries/General/C/CitableImage"
 "/home/user/.julia/registries/General/T/Trixi2Img"
 "/home/user/.julia/registries/General/I/ImPlot"
 "/home/user/.julia/registries/General/S/StableDQMC"
 "/home/user/.julia/registries/General/S/Strapping"
 [...]
```
Do not abuse this function!

You use `analyze_from_registry!(root, joinpath(general_registry(), "F", "Flux"))` to clone
the package to a particular directory `root` which is not cleaned up afterwards, and likewise
can pass a vector of paths to use a threaded loop over them.

You can also directly analyze the source code of a package via `analyze`, for example

```julia
julia> using AnalyzeRegistry

julia> analyze(pkgdir(AnalyzeRegistry))
Package AnalyzeRegistry:
  * repo: 
  * uuid: e713c705-17e4-4cec-abe0-95bf5bf3e10c
  * is reachable: true
  * has documentation: false
  * has tests: true
  * has continuous integration: true
    * GitHub Actions
  * has license(s) in file: MIT
    * filename: LICENSE
    * OSI approved: true
  * lines of Julia code in `src`: 328
  * lines of Julia code in `test`: 58
```

## License

The `AnalyzeRegistry.jl` package is licensed under the MIT "Expat" License.  The
original author is Mosè Giordano.
