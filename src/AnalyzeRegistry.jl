module AnalyzeRegistry

# Standard libraries
using Pkg, TOML
# Third-party packages
using FLoops # for the `@floops` macro
using MicroCollections # for `EmptyVector` and `SingletonVector`
using BangBang # for `append!!`

export general_registry, find_packages, analyze

struct Package
    name::String # name of the package
    repo::String # URL of the repository
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
end
function Package(name, repo;
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
                 )
    return Package(name, repo, reachable, docs, runtests, github_actions, travis,
                   appveyor, cirrus, circle, drone, buildkite, azure_pipelines, gitlab_pipeline)
end

function Base.show(io::IO, p::Package)
    body = """
        Package $(p.name):
          * repo: $(p.repo)
          * is reachable: $(p.reachable)
        """
    if p.reachable
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
    packages = TOML.parsefile(joinpath(general_registry(), "Registry.toml"))["packages"]
    # Get the directories of all packages.  Filter out JLL packages: they are
    # automatically generated and we know that they don't have testing nor
    # documentation.
    packages_dirs = [joinpath(dir, p["path"]) for (_, p) in packages if !endswith(p["name"], "_jll")]
end

"""
    analyze(dir::AbstractString) -> Package

Analyze the package whose entry in the registry is in the `dir` directory.
NOTE: the git repository of the package will be cloned, so you need Internet
access to use this package.

## Example
```julia
julia> analyze(joinpath(general_registry(), "B", "BinaryBuilder"))
Package BinaryBuilder:
  * repo: https://github.com/JuliaPackaging/BinaryBuilder.jl.git
  * is reachable: true
  * has documentation: true
  * has tests: true
  * has continuous integration: true
    * GitHub Actions
    * Azure Pipelines
```
"""
function analyze(dir::AbstractString)
    # Parse the `Package.toml` file in the given directory.
    toml = TOML.parsefile(joinpath(dir, "Package.toml"))
    name = toml["name"]::String
    repo = toml["repo"]::String
    # Clone the repository into a temporary directory
    package = mktempdir() do dest
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
        if reachable
            docs = isfile(joinpath(dest, "docs", "make.jl")) || isfile(joinpath(dest, "doc", "make.jl"))
            testpath = joinpath(dest, "test", "runtests.jl")
            runtests = isfile(testpath) && (length(readlines(testpath))>6 || length(readdir(joinpath(dest, "test")))>1)
            travis = isfile(joinpath(dest, ".travis.yml"))
            appveyor = isfile(joinpath(dest, "appveyor.yml"))
            cirrus = isfile(joinpath(dest, ".cirrus.yml"))
            circle = isfile(joinpath(dest, ".circleci", "config.yml"))
            drone = isfile(joinpath(dest, ".drone.yml"))
            azure_pipelines = isfile(joinpath(dest, "azure-pipelines.yml"))
            buildkite = isfile(joinpath(dest, ".buildkite", "pipeline.yml"))
            gitlab_pipeline = isfile(joinpath(dest, ".gitlab-ci.yml"))
            github_workflows = joinpath(dest, ".github", "workflows")
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
            Package(name, repo; reachable, docs, runtests, travis, appveyor, cirrus,
                    circle, drone, buildkite, azure_pipelines, gitlab_pipeline, github_actions)
        else
            Package(name, repo)
        end
    end
    return package
end

"""
    analyze(packages::AbstractVector{<:AbstractString}) -> Vector{Package}

Analyze all packages in the iterable `packages`, using threads.  Return a
`Vector{Package}`.
"""
function analyze(packages::AbstractVector{<:AbstractString})
    @floop for p in packages
        ps = SingletonVector((analyze(p),))
        @reduce(result = append!!(EmptyVector(), ps))
    end
    result
end

end # module
