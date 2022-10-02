module PackageAnalyzer

# Standard libraries
using Pkg, TOML, UUIDs, Printf
# Third-party packages
using LicenseCheck # for `find_license` and `is_osi_approved`
using JSON3 # for interfacing with `tokei` to count lines of code
using Tokei_jll # count lines of code
using GitHub # Use GitHub API to get extra information about the repo
using Git
using RegistryInstances
using Downloads
using Tar
using CodecZlib

export general_registry, find_package, find_packages, find_packages_in_manifest
export analyze, analyze!, analyze_manifest

const AbstractVersion = Union{VersionNumber,Symbol}

# borrowed from <https://github.com/JuliaRegistries/RegistryTools.jl/blob/841a56d8274e2857e3fd5ea993ba698cdbf51849/src/builtin_pkgs.jl>
const stdlibs = isdefined(Pkg.Types, :stdlib) ? Pkg.Types.stdlib : Pkg.Types.stdlibs
# Julia 1.8 changed from `name` to `(name, version)`.
get_stdlib_name(s::AbstractString) = s
get_stdlib_name(s::Tuple) = first(s)
const STDLIBS = Dict(k => get_stdlib_name(v) for (k, v) in stdlibs())

include("count_loc.jl")

const LicenseTableEltype = @NamedTuple{license_filename::String, licenses_found::Vector{String}, license_file_percent_covered::Float64}
const ContributionTableElType = @NamedTuple{login::Union{String,Missing}, id::Union{Int,Missing}, name::Union{String,Missing}, type::String, contributions::Int}

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
    license_files::Vector{LicenseTableEltype} # a table of all possible license files
    licenses_in_project::Vector{String} # any licenses in the `license` key of the Project.toml
    lines_of_code::Vector{LoCTableEltype} # table of lines of code
    contributors::Vector{ContributionTableElType} # table of contributor data
    version::AbstractVersion # the version was asked to be analyzed (`dev` or a `VersionNumber`)
    tree_hash::String # the tree hash of the code that was analyzed
end
function Package(name, uuid, repo;
                 subdir="",
                 reachable=false,
                 docs=false,
                 runtests=false,
                 github_actions=false,
                 travis=false,
                 appveyor=false,
                 cirrus=false,
                 circle=false,
                 drone=false,
                 buildkite=false,
                 azure_pipelines=false,
                 gitlab_pipeline=false,
                 license_files=LicenseTableEltype[],
                 licenses_in_project=String[],
                 lines_of_code=LoCTableEltype[],
                 contributors=ContributionTableElType[],
                 version=v"0",
                 tree_hash=""
                 )
    return Package(name, uuid, repo, subdir, reachable, docs, runtests, github_actions, travis,
                   appveyor, cirrus, circle, drone, buildkite, azure_pipelines, gitlab_pipeline,
                   license_files, licenses_in_project, lines_of_code, contributors, version, tree_hash)
end

# define `isequal`, `==`, and `hash` just in terms of the fields
for f in (:isequal, :(==))
    @eval begin
        function Base.$f(A::Package, B::Package)
            for i = 1:fieldcount(Package)
                $f(getfield(A, i), getfield(B, i)) || return false
            end
            true
        end
    end
end

Base.hash(A::Package, h::UInt) = hash(:Package, hash(ntuple(i -> getfield(A, i), fieldcount(Package)), h))

function Base.show(io::IO, p::Package)
    body = """
        Package $(p.name):
          * repo: $(p.repo)
        """
    if !isempty(p.subdir)
        body *= """
            * in subdirectory: $(p.subdir)
        """
    end
    body *= """
          * uuid: $(p.uuid)
          * version: $(p.version)
          * is reachable: $(p.reachable)
        """
    if p.reachable
        body *= """
          * tree hash: $(p.tree_hash)
        """
        if !isempty(p.lines_of_code)
            l_src = count_julia_loc(p, "src")
            l_test = count_julia_loc(p, "test")
            l_docs = count_docs(p)
            l_readme = count_readme(p)

            p_test = @sprintf("%.1f", 100 * l_test / (l_test + l_src))
            p_docs = @sprintf("%.1f", 100 * l_docs / (l_docs + l_src))
            body *= """
                  * Julia code in `src`: $(l_src) lines
                  * Julia code in `test`: $(l_test) lines ($(p_test)% of `test` + `src`)
                  * documention in `docs`: $(l_docs) lines ($(p_docs)% of `docs` + `src`)
                  * documention in README: $(l_readme) lines
                """
        end
        if isempty(p.license_files)
            body *= "  * no license found\n"
        else
            lic = p.license_files[1]
            license_string = join(lic.licenses_found, ", ")
            body *= "  * has license(s) in file: $(license_string)\n"
            body *= "    * filename: $(lic.license_filename)\n"
            body *= "    * OSI approved: $(all(is_osi_approved, lic.licenses_found))\n"
        end
        if !isempty(p.licenses_in_project)
            lic_project = join(p.licenses_in_project, ", ")
            body *= "  * has license(s) in Project.toml: $(lic_project)\n"
            body *= "    * OSI approved: $(all(is_osi_approved, p.licenses_in_project))\n"
        end
        if !isempty(p.contributors)
            n_anon = count_contributors(p; type="Anonymous")
            body *= "  * number of contributors: $(count_contributors(p)) (and $(n_anon) anonymous contributors)\n"
            body *= "  * number of commits: $(count_commits(p))\n"
        end
        body *= """
              * has `docs/make.jl`: $(p.docs)
              * has `test/runtests.jl`: $(p.runtests)
            """
        ci_services = (p.github_actions => "GitHub Actions",
                       p.travis => "Travis",
                       p.appveyor => "AppVeyor",
                       p.cirrus => "Cirrus",
                       p.circle => "Circle",
                       p.drone => "Drone CI",
                       p.buildkite => "Buildkite",
                       p.azure_pipelines => "Azure Pipelines",
                       p.gitlab_pipeline => "GitLab Pipeline",
                       )
        if any(first.(ci_services))
            body *= "  * has continuous integration: true\n"
            for (k, v) in ci_services
                if k
                    body *= "    * $(v)\n"
                end
            end
        else
            body *= "  * has continuous integration: false\n"
        end
    end
    print(io, strip(body))
end


# We could have:
# * release version: registry + version or registry + tree_hash (equivalent)
# * Pkg.add: path + tree_hash, or url + tree_hash
# * Pkg.dev: just path or url
#
# Additionally, the user may pass us just a path, which we treat like Pkg.dev
# or the user may pass us a Module, which we treat the same way (via pkgdir),
# or they may ask for the dev version, which again we treat the same way.
#
# They may ask for a specific version, which we treat like release.
abstract type PkgSource end

struct Release <: PkgSource
    entry::PkgEntry
    version::Union{VersionNumber, Nothing} # nothing means latest?
end

Base.@kwdef struct Added <: PkgSource
    path::Union{String, Nothing} = nothing
    repo_url::Union{String, Nothing} = nothing
    tree_hash::String = ""
end

Base.@kwdef struct Dev <: PkgSource
    path::Union{String, Nothing} = nothing
    repo_url::Union{String, Nothing} = nothing
end

include("find_packages.jl")
include("entrypoints.jl")
include("core.jl")
include("parallel.jl")
include("utilities.jl")

"""
    analyze(package::PkgEntry; auth::GitHub.Authorization=github_auth(), sleep=0, version::AbstractVersion=:dev) -> Package
    analyze(packages::AbstractVector{<:PkgEntry}; auth::GitHub.Authorization=github_auth(), sleep=0, version::AbstractVersion=:dev) -> Vector{Package}

Analyzes a package or list of packages using the information in their directory
in a registry by creating a temporary directory and calling `analyze!`,
cleaning up the temporary directory afterwards.

If the GitHub authentication is non-anonymous and the repository is on GitHub,
the list of contributors to the repository is also collected after waiting for
`sleep` seconds (useful to avoid getting rate-limited by GitHub).  Only the
number of contributors will be shown in the summary.  See
[`PackageAnalyzer.github_auth`](@ref) to obtain a GitHub authentication.

## Example
```julia
julia> analyze(find_package("BinaryBuilder"))
Package BinaryBuilder:
  * repo: https://github.com/JuliaPackaging/BinaryBuilder.jl.git
  * uuid: 12aac903-9f7c-5d81-afc2-d9565ea332ae
  * version: dev
  * is reachable: true
  * tree hash: 13335f33356c8df9899472634e02552fd6f99ce4
  * Julia code in `src`: 4994 lines
  * Julia code in `test`: 1795 lines (26.4% of `test` + `src`)
  * documention in `docs`: 1129 lines (18.4% of `docs` + `src`)
  * documention in README: 22 lines
  * has license(s) in file: MIT
    * filename: LICENSE.md
    * OSI approved: true
  * has `docs/make.jl`: true
  * has `test/runtests.jl`: true
  * has continuous integration: true
    * GitHub Actions
    * Azure Pipelines

```
"""
function analyze(p; auth::GitHub.Authorization=github_auth(), sleep=0, version::AbstractVersion=:dev)
    root = mktempdir()
    analyze!(root, p; auth, sleep, version)
end

end # module
