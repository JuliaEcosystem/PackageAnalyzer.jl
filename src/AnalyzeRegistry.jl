module AnalyzeRegistry

# Standard libraries
using Pkg, TOML, UUIDs
# Third-party packages
using FLoops # for the `@floops` macro
using MicroCollections # for `EmptyVector` and `SingletonVector`
using BangBang # for `append!!`
using LicenseCheck # for `find_license` and `is_osi_approved`
using JSON3 # for interfacing with `tokei` to count lines of code
using Tokei_jll # count lines of code

export general_registry, find_packages, analyze, analyze_from_registry, analyze_from_registry!

include("count_loc.jl")

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
    licenses_in_project::Vector{String} # any licenses in the `license` key of the Project.toml
    lines_of_code::Vector{LoCTableEltype}
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
                 license_filename=missing,
                 licenses_found=String[],
                 license_file_percent_covered=missing,
                 licenses_in_project=String[],
                 lines_of_code=Vector{LoCTableEltype}(),
                 )
    return Package(name, uuid, repo, subdir, reachable, docs, runtests, github_actions, travis,
                   appveyor, cirrus, circle, drone, buildkite, azure_pipelines, gitlab_pipeline,
                   license_filename, licenses_found, license_file_percent_covered, licenses_in_project,
                   lines_of_code)
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
          * uuid: $(p.uuid)
          * is reachable: $(p.reachable)
        """
    if p.reachable
        if !isempty(p.lines_of_code)
            body *= """
                  * lines of Julia code in `src`: $(count_julia_loc(p.lines_of_code, "src"))
                  * lines of Julia code in `test`: $(count_julia_loc(p.lines_of_code, "test"))
                """
        end
        if isempty(p.licenses_found)
            body *= "  * no license found\n"
        else
            lic = join(p.licenses_found, ", ")
            body *= "  * has license(s) in file: $lic\n"
            body *= "    * filename: $(p.license_filename)\n"
            body *= "    * OSI approved: $(all(is_osi_approved, p.licenses_found))\n"
        end
        if !isempty(p.licenses_in_project)
            lic_project = join(p.licenses_in_project, ", ")
            body *= "  * has license(s) in Project.toml: $(lic_project)\n"
            body *= "    * OSI approved: $(all(is_osi_approved, p.licenses_in_project))\n"
        end
        body *= """
              * has documentation: $(p.docs)
              * has tests: $(p.runtests)
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

"""
    general_registry() -> String

Guess the path of the General registry.
"""
general_registry() =
    first([joinpath(d, "registries", "General") for d in Pkg.depots() if isfile(joinpath(d, "registries", "General", "Registry.toml"))])

"""
    find_packages(dir = general_registry()) -> Vector{String}

Find all packages in the given registry, the General registry by default.
Return a vector with the paths to the directories of each package in the
registry.
"""
function find_packages(dir = general_registry())
    # Get the list of packages in the registry by parsing the `Registry.toml`
    # file in the given directory.
    packages = TOML.parsefile(joinpath(dir, "Registry.toml"))["packages"]
    # Get the directories of all packages.  Filter out JLL packages: they are
    # automatically generated and we know that they don't have testing nor
    # documentation.
    packages_dirs = [joinpath(dir, p["path"]) for (_, p) in packages if !endswith(p["name"], "_jll")]
end

"""
    analyze_from_registry!(root, dir::AbstractString) -> Package

Analyze the package whose entry in the registry is in the `dir` directory,
cloning the package code to `joinpath(root, uuid)` where `uuid` is the UUID
of the package, if such a directory does not already exist.

"""
function analyze_from_registry!(root, dir::AbstractString)
    # Parse the `Package.toml` file in the given directory.
    toml = TOML.parsefile(joinpath(dir, "Package.toml"))
    name = toml["name"]::String
    uuid_string = toml["uuid"]::String
    uuid = UUID(uuid_string)
    repo = toml["repo"]::String
    subdir = get(toml, "subdir", "")::String

    dest = joinpath(root, uuid_string)

    isdir(dest) && return analyze(dest; repo, subdir)

    reachable = try
        # Clone only latest commit on the default branch.  Note: some
        # repositories aren't reachable because the author made them private
        # or deleted them.  In these cases git would ask for username and
        # password, provide it with fake values just to move on:
        # https://stackoverflow.com/a/65705346/2442087
        run(pipeline(`git clone -q --depth 1 --config credential.helper='!f() { echo -e "username=git\npassword="; }; f' $(repo) $(dest)`; stderr=devnull))
        true
    catch
        # The repository may be unreachable
        false
    end
    return reachable ? analyze(dest; repo, reachable, subdir) : Package(name, uuid, repo; subdir)
end

"""
    analyze_from_registry!(root, packages::AbstractVector{<:AbstractString}) -> Vector{Package}

Analyze all packages in the iterable `packages`, using threads, cloning them to `root`
if a directory with their `uuid` does not already exist.  Returns a
`Vector{Package}`.
"""
function analyze_from_registry!(root, packages::AbstractVector{<:AbstractString})
    @floop for p in packages
        ps = SingletonVector((analyze_from_registry!(root, p),))
        @reduce(result = append!!(EmptyVector(), ps))
    end
    result
end

"""
    analyze_from_registry(dir::AbstractString) -> Package
    analyze_from_registry(packages::AbstractVector{<:AbstractString}) -> Vector{Package}

Analyzes a package or list of packages using the information in their directory
in a registry by creating a temporary directory and calling `analyze_from_registry!`,
cleaning up the temporary directory afterwards.

## Example
```julia
julia> analyze_from_registry(joinpath(general_registry(), "B", "BinaryBuilder"))
Package BinaryBuilder:
  * repo: https://github.com/JuliaPackaging/BinaryBuilder.jl.git
  * uuid: 12aac903-9f7c-5d81-afc2-d9565ea332ae
  * is reachable: true
  * lines of Julia code in `src`: 4733
  * lines of Julia code in `test`: 1520
  * has license(s) in file: MIT
    * filename: LICENSE.md
    * OSI approved: true
  * has documentation: true
  * has tests: true
  * has continuous integration: true
    * GitHub Actions
    * Azure Pipelines

```
"""
function analyze_from_registry(p)
    mktempdir() do root
        analyze_from_registry!(root, p)
    end
end

function parse_project(dir)
    bad_project = (; name = "Invalid Project.toml", uuid = UUID(UInt128(0)), licenses_in_project=String[])
    project_path = joinpath(dir, "Project.toml")
    if !isfile(project_path)
        project_path = joinpath(dir, "JuliaProject.toml")
    end
    isfile(project_path) || return bad_project
    project = TOML.tryparsefile(project_path)
    project isa TOML.ParserError && return bad_project
    haskey(project, "name") && haskey(project, "uuid") || return bad_project
    uuid = tryparse(UUID, project["uuid"]::String)
    uuid === nothing && return bad_project
    licenses_in_project = get(project, "license", String[])
    if licenses_in_project isa String
        licenses_in_project = [licenses_in_project]
    end
    return (; name = project["name"]::String, uuid, licenses_in_project)
end

"""
    analyze(dir::AbstractString; repo = "", reachable=true, name=nothing, uuid=nothing)

Analyze the package whose source code is located at `dir`. Optionally `repo`
and `reachable` a boolean indicating whether or not the package is reachable online, since
these can't be inferred from the source code. If `name` or `uuid` are `nothing`, the
directories `Project.toml` is parsed to infer the package's name and UUID.

## Example
```julia
julia> analyze(pkgdir(AnalyzeRegistry))
Package AnalyzeRegistry:
  * repo: 
  * uuid: e713c705-17e4-4cec-abe0-95bf5bf3e10c
  * is reachable: true
  * lines of Julia code in `src`: 327
  * lines of Julia code in `test`: 58
  * has license(s) in file: MIT
    * filename: LICENSE
    * OSI approved: true
  * has documentation: false
  * has tests: true
  * has continuous integration: true
    * GitHub Actions

```
"""
function analyze(dir::AbstractString; repo = "", reachable=true, subdir="")
    # we will look for docs, tests, license, and count lines of code
    # in the `pkgdir`; we will look for CI in the `dir`.
    pkgdir = joinpath(dir, subdir)
    name, uuid, licenses_in_project = parse_project(pkgdir)
    docs = isfile(joinpath(pkgdir, "docs", "make.jl")) || isfile(joinpath(pkgdir, "doc", "make.jl"))
    runtests = isfile(joinpath(pkgdir, "test", "runtests.jl"))
    travis = isfile(joinpath(dir, ".travis.yml"))
    appveyor = isfile(joinpath(dir, "appveyor.yml"))
    cirrus = isfile(joinpath(dir, ".cirrus.yml"))
    circle = isfile(joinpath(dir, ".circleci", "config.yml"))
    drone = isfile(joinpath(dir, ".drone.yml"))
    azure_pipelines = isfile(joinpath(dir, "azure-pipelines.yml"))
    buildkite = isfile(joinpath(dir, ".buildkite", "pipeline.yml"))
    gitlab_pipeline = isfile(joinpath(dir, ".gitlab-ci.yml"))
    github_workflows = joinpath(dir, ".github", "workflows")
    if isdir(github_workflows)
        # Find all workflows
        files = readdir(github_workflows)
        # Exclude TagBot and CompatHelper
        filter(f -> lowercase(f) ∉ ("compathelper.yml", "tagbot.yml"), files)
        # Assume all other files are GitHub Actions for CI.  May not
        # _always_ be the case, but it's a good first-order approximation.
        github_actions = length(files) > 0
    else
        github_actions = false
    end
    lic = find_license(pkgdir)
    if lic === nothing
        lic = (; license_filename=missing, licenses_found=String[], license_file_percent_covered=missing)
    end
    lines_of_code = count_loc(pkgdir)
    Package(name, uuid, repo; subdir, reachable, docs, runtests, travis, appveyor, cirrus,
            circle, drone, buildkite, azure_pipelines, gitlab_pipeline, github_actions,
            lic..., licenses_in_project, lines_of_code)
end

end # module
