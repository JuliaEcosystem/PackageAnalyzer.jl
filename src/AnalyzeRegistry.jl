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
using GitHub # Use GitHub API to get extra information about the repo

export general_registry, find_package, find_packages
export analyze, analyze_from_registry, analyze_from_registry!

include("count_loc.jl")
const LicenseTableEltype=@NamedTuple{license_filename::String, licenses_found::Vector{String}, license_file_percent_covered::Float64}

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
    contributors::Dict{String,Int} # Dictionary contributors => contributions
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
                 lines_of_code=Vector{LoCTableEltype}(),
                 contributors=Dict{String,Int}(),
                 )
    return Package(name, uuid, repo, subdir, reachable, docs, runtests, github_actions, travis,
                   appveyor, cirrus, circle, drone, buildkite, azure_pipelines, gitlab_pipeline,
                   license_files, licenses_in_project, lines_of_code, contributors)
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
          * is reachable: $(p.reachable)
        """
    if p.reachable
        if !isempty(p.lines_of_code)
            body *= """
                  * lines of Julia code in `src`: $(count_julia_loc(p.lines_of_code, "src"))
                  * lines of Julia code in `test`: $(count_julia_loc(p.lines_of_code, "test"))
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
            body *= "  * number of contributors: $(length(p.contributors))\n"
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
    find_package(pkg; registry = general_registry()) -> String

Returns the path to the entry in `registry` for the package `pkg`.
The singular version of [`find_packages`](@ref).
"""
find_package(pkg::AbstractString; registry=general_registry()) = only(find_packages([pkg]; registry))

"""
    find_packages(; registry = general_registry()) -> Vector{String}
    find_packages(names::AbstractString...; registry = general_registry()) -> Vector{String}
    find_packages(names; registry = general_registry()) -> Vector{String}

Find all packages in the given registry (specified by the `registry` keyword argument),
the General registry by default. Return a vector with the paths to the directories
of each package in the registry.

Pass a list of package `names` as the first argument to return the paths corresponding to those packages,
or individual package names as separate arguments.
"""
find_packages

find_packages(names::AbstractString...; registry = general_registry()) =  find_packages(names; registry=registry)

function find_packages(names; registry = general_registry())
    if names !== nothing
        paths = String[]
        for name in names
            path = joinpath(registry, string(uppercase(first(name))), name)
            if isdir(path)
               push!(paths, path)
            else
                @error("Could not find package in registry!", name, path)
            end
        end
        return paths
    end
end

# The UUID of the "julia" pseudo-package in the General registry
const JULIA_UUID = "1222c4b2-2114-5bfd-aeef-88e4692bbb3e"

function find_packages(; registry = general_registry(),
                       filter = (uuid, p) -> !endswith(p["name"], "_jll") && uuid != JULIA_UUID)
    # Get the list of packages in the registry by parsing the `Registry.toml`
    # file in the given directory.
    packages = TOML.parsefile(joinpath(registry, "Registry.toml"))["packages"]
    # Get the directories of all packages.  Filter out JLL packages: they are
    # automatically generated and we know that they don't have testing nor
    # documentation. We also filter out the "julia" package which is not a real
    # package and just points at the Julia source code.
    return [joinpath(registry, splitpath(p["path"])...) for (uuid, p) in packages if filter(uuid, p)]
end


"""
    AnalyzeRegistry.github_auth(token::String="")

Obtain a GitHub authetication.  Use the `token` argument if it is non-empty,
otherwise use the `GITHUB_TOKEN` and `GITHUB_AUTH` environment variables, if set
and of length 40.  If all these methods fail, return an anonymous
authentication.
"""
function github_auth(token::String="")
    auth = if !isempty(token)
        GitHub.authenticate(token)
    elseif haskey(ENV, "GITHUB_TOKEN") && length(ENV["GITHUB_TOKEN"]) == 40
        GitHub.authenticate(ENV["GITHUB_TOKEN"])
    elseif haskey(ENV, "GITHUB_AUTH") && length(ENV["GITHUB_AUTH"]) == 40
        GitHub.authenticate(ENV["GITHUB_AUTH"])
    else
        GitHub.AnonymousAuth()
    end
end

"""
    analyze_from_registry!(root, dir::AbstractString; auth::GitHub.Authorization=github_auth()) -> Package

Analyze the package whose entry in the registry is in the `dir` directory,
cloning the package code to `joinpath(root, uuid)` where `uuid` is the UUID
of the package, if such a directory does not already exist.

If the GitHub authentication is non-anonymous and the repository is on GitHub,
the list of contributors to the repository is also collected.  Only the number
of contributors will be shown in the summary.  See
[`AnalyzeRegistry.github_auth`](@ref) to obtain a GitHub authentication.
"""
function analyze_from_registry!(root, dir::AbstractString; auth::GitHub.Authorization=github_auth())
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
    return reachable ? analyze(dest; repo, reachable, subdir, auth) : Package(name, uuid, repo; subdir)
end

"""
    analyze_from_registry!(root, packages::AbstractVector{<:AbstractString}; auth::GitHub.Authorization=github_auth()) -> Vector{Package}

Analyze all packages in the iterable `packages`, using threads, cloning them to `root`
if a directory with their `uuid` does not already exist.  Returns a
`Vector{Package}`.

If the GitHub authentication is non-anonymous and the repository is on GitHub,
the list of contributors to the repositories is also collected.  See
[`AnalyzeRegistry.github_auth`](@ref) to obtain a GitHub authentication.

"""
function analyze_from_registry!(root, packages::AbstractVector{<:AbstractString}; auth::GitHub.Authorization=github_auth())
    @floop for p in packages
        ps = SingletonVector((analyze_from_registry!(root, p; auth),))
        @reduce(result = append!!(EmptyVector(), ps))
    end
    result
end

"""
    analyze_from_registry(dir::AbstractString; auth::GitHub.Authorization=github_auth()) -> Package
    analyze_from_registry(packages::AbstractVector{<:AbstractString}; auth::GitHub.Authorization=github_auth()) -> Vector{Package}

Analyzes a package or list of packages using the information in their directory
in a registry by creating a temporary directory and calling `analyze_from_registry!`,
cleaning up the temporary directory afterwards.

If the GitHub authentication is non-anonymous and the repository is on GitHub,
the list of contributors to the repository is also collected.  Only the number
of contributors will be shown in the summary.  See
[`AnalyzeRegistry.github_auth`](@ref) to obtain a GitHub authentication.

## Example
```julia
julia> analyze_from_registry(joinpath(general_registry(), "B", "BinaryBuilder"))
Package BinaryBuilder:
  * repo: https://github.com/JuliaPackaging/BinaryBuilder.jl.git
  * uuid: 12aac903-9f7c-5d81-afc2-d9565ea332ae
  * is reachable: true
  * lines of Julia code in `src`: 4724
  * lines of Julia code in `test`: 1542
  * has license(s) in file: MIT
    * filename: LICENSE.md
    * OSI approved: true
  * number of contributors: 50
  * has documentation: true
  * has tests: true
  * has continuous integration: true
    * GitHub Actions
    * Azure Pipelines

```
"""
function analyze_from_registry(p; auth::GitHub.Authorization=github_auth())
    mktempdir() do root
        analyze_from_registry!(root, p; auth)
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
    analyze(dir::AbstractString; repo = "", reachable=true, name=nothing, uuid=nothing, auth::GitHub.Authorization=github_auth())

Analyze the package whose source code is located at `dir`. Optionally `repo`
and `reachable` a boolean indicating whether or not the package is reachable online, since
these can't be inferred from the source code. If `name` or `uuid` are `nothing`, the
directories `Project.toml` is parsed to infer the package's name and UUID.

If the GitHub authentication is non-anonymous and the repository is on GitHub,
the list of contributors to the repository is also collected.  Only the number
of contributors will be shown in the summary.  See
[`AnalyzeRegistry.github_auth`](@ref) to obtain a GitHub authentication.

## Example

```julia
julia> using DataFrames

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
"""
function analyze(dir::AbstractString; repo = "", reachable=true, subdir="", auth::GitHub.Authorization=github_auth())
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
    license_files = find_licenses(dir)
    if isdir(pkgdir)
        if !isempty(subdir)
            # Look for licenses at top-level and in the subdirectory
            subdir_licenses_files = [(; license_filename = joinpath(subdir, row.license_filename), row.licenses_found, row.license_file_percent_covered) for row in find_licenses(pkgdir)]
            license_files = [subdir_licenses_files; license_files]
        end
        lines_of_code = count_loc(pkgdir)
    else
        license_files = LicenseTableEltype[]
        lines_of_code = LoCTableEltype[]
    end

    # If the repository is on GitHub and we have a non-anonymous GitHub
    # authentication, get the list of contributors
    contributors = if !(auth isa GitHub.AnonymousAuth) && occursin("github.com", repo)
        repo_name = replace(replace(repo, r"^https://github\.com/" => ""), r"\.git$" => "")
        # Exclude commits made by known bots, including `@staticfloat`
        #   130920   => staticfloat (when he has one commit, it's most likely an automated one)
        #   30578772 => femtocleaner[bot]
        #   41898282 => github-actions[bot]
        #   50554310 => TagBot
        Dict{String,Int}(
            c["contributor"].login => c["contributions"] for c in GitHub.contributors(GitHub.repo(repo_name; auth); auth)[1] if c["contributor"].id ∉ (30578772, 41898282, 50554310) && !(c["contributor"].id == 130920 && c["contributions"] == 1)
        )
    else
        Dict{String,Int}()
    end

    Package(name, uuid, repo; subdir, reachable, docs, runtests, travis, appveyor, cirrus,
            circle, drone, buildkite, azure_pipelines, gitlab_pipeline, github_actions,
            license_files, licenses_in_project, lines_of_code, contributors)
end

end # module
