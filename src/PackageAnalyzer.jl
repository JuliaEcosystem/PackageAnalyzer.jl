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
export analyze, analyze!

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
    version::AbstractVersion
    tree_hash::String
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
          * is reachable: $(p.reachable)
        """
    if p.reachable
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

const GENERAL_REGISTRY_UUID = UUID("23338594-aafe-5451-b93e-139f81909106")

"""
    general_registry() -> RegistryInstance

Return the `RegistryInstance` associated to the General registry.
"""
function general_registry()
    registries = reachable_registries()
    idx = findfirst(r -> r.uuid == GENERAL_REGISTRY_UUID, registries)
    if idx === nothing
        throw(ArgumentError("Could not find General registry! Is it installed?"))
    else
        return registries[idx]
    end
end


"""
    find_package(pkg; registry = general_registry()) -> RegistryEntry

Returns the [RegistryEntry](@ref) for the package `pkg`.
The singular version of [`find_packages`](@ref).
"""
function find_package(pkg::AbstractString; registry = general_registry())
    pkg_entries = find_packages([pkg]; registry)
    if isempty(pkg_entries)
        if pkg ∈ values(STDLIBS)
            throw(ArgumentError("Standard library $pkg not present in registry"))
        else
            throw(ArgumentError("$pkg not found in registry"))
        end
    end
    return only(pkg_entries)
end

"""
    find_packages(; registry = general_registry()) -> Vector{RegistryEntry}
    find_packages(names::AbstractString...; registry = general_registry()) -> Vector{RegistryEntry}
    find_packages(names; registry = general_registry()) -> Vector{RegistryEntry}

Find all packages in the given registry (specified by the `registry` keyword
argument), the General registry by default. Return a vector of
[RegistryEntry](@ref) pointing to to the directories of each package in the
registry.

Pass a list of package `names` as the first argument to return the paths corresponding to those packages,
or individual package names as separate arguments.
"""
find_packages

find_packages(names::AbstractString...; registry=general_registry()) = find_packages(names; registry=registry)

function find_packages(names; registry=general_registry())
    if names !== nothing
        entries = PkgEntry[]
        for name in names
            uuids = uuids_from_name(registry, name)
            if length(uuids) > 1
                error("There are more than one packages with name $(name)! These have UUIDs $uuids")
            elseif length(uuids) == 1
                push!(entries, registry.pkgs[only(uuids)])
            elseif name ∉ values(STDLIBS)
                @error("Could not find package in registry!", name)
            end
        end
        return entries
    end
end

# The UUID of the "julia" pseudo-package in the General registry
const JULIA_UUID = UUID("1222c4b2-2114-5bfd-aeef-88e4692bbb3e")

function find_packages(; registry=general_registry(),
    filter=((uuid, p),) -> !endswith(p.name, "_jll") && uuid != JULIA_UUID)
    # Get the PkgEntry's of all packages in the registry.  Filter out JLL packages: they are
    # automatically generated and we know that they don't have testing nor
    # documentation. We also filter out the "julia" package which is not a real
    # package and just points at the Julia source code.
    return collect(values(Base.filter(filter, registry.pkgs)))
end

"""
    PackageAnalyzer.github_auth(token::String="")

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
    analyze!(root, package::PkgEntry; auth::GitHub.Authorization=github_auth(), version::$AbstractVersion=:dev) -> Package

Analyze the package whose entry in the registry is in the `dir` directory,
cloning the package code to `joinpath(root, uuid)` where `uuid` is the UUID
of the package, if such a directory does not already exist.

If the GitHub authentication is non-anonymous and the repository is on GitHub,
the list of contributors to the repository is also collected, after waiting for
`sleep` seconds.  Only the number of contributors will be shown in the summary.
See [`PackageAnalyzer.github_auth`](@ref) to obtain a GitHub authentication.
"""
function analyze!(root, pkg::PkgEntry; auth::GitHub.Authorization=github_auth(), sleep=0, version::AbstractVersion=:dev)
    name = pkg.name
    uuid = pkg.uuid
    info = registry_info(pkg)
    repo = info.repo
    subdir = something(info.subdir, "")

    if version === :dev
        tree_sha = nothing
    else
        info = registry_info(pkg)
        if version === :stable
            version = maximum(keys(info.version_info))
            tree_sha = info.version_info[version].git_tree_sha1
        elseif version isa Symbol
            error("Unrecognized version $version. Must be `:dev`, `:stable`, or a `VersionNumber`.")
        else
            tree_sha = info.version_info[version].git_tree_sha1
        end
    end
    if tree_sha === nothing
        tree_hash = nothing
    else
        tree_hash = bytes2hex(tree_sha.bytes)
    end

    @debug "Analyzing version $version of $name"

    vs = tree_sha === nothing ? "dev" : Base.version_slug(uuid, tree_sha)
    dest = joinpath(root, name, vs)

    # Re-use logic.
    # We can never re-use dev, because maybe it got updated.
    # However if we have an actual tree hash there, we can use it.
    if isdir(dest)
        if version === :dev
            # Stale; cleanup
            rm(dest; recursive=true)
        else
            # We can re-use it! We've keyed off pkg uuid and tree hash.
            # We assume no one's messed with the files since.
            # We pass `only_subdir=true` since that's the state we should be in for non-dev versions.
            return analyze_path(dest; repo, subdir, auth, sleep, only_subdir=true, version)
        end
    end

    return analyze_path!(dest, repo; name, uuid, subdir, auth, sleep, tree_hash, version)
end

function github_extract_code!(dest::AbstractString, user::AbstractString, repo::AbstractString, tree_hash::AbstractString; auth)
    path = "/repos/$(user)/$(repo)/tarball/$(tree_hash)"
    resp = GitHub.gh_get(GitHub.DEFAULT_API, path; auth)
    tmp = mktempdir()
    Tar.extract(GzipDecompressorStream(IOBuffer(resp.body)), tmp)
    files = only(readdir(tmp; join=true))
    isdir(dest) || mkdir(dest)
    mv(files, dest; force=true)
    return nothing
end

"""
    analyze_path!(dest::AbstractString, repo::AbstractString; name="", uuid=UUID(UInt128(0)), subdir="", auth=github_auth(), sleep=0, tree_hash=nothing) -> Package

Analyze the Julia package located at the URL given by `repo` by cloning it to `dest`
and calling `analyze_path(dest)`. If `tree_hash !== nothing`, only the code associated
to that tree hash is placed into `dest`. That allows analyzing particular version numbers,
but in the case of packages in subdirectories, it also means that top-level information
(like CI workflows) is unavailable.

If the clone fails, it returns a `Package` with `reachable=false`. If a `name` and `uuid` are provided,
these are used to populate the corresponding fields of the `Package`. If the clone succeeds, the `name`
and `uuid` are taken instead from the Project.toml in the package itself, and the values passed here
are ignored.

If the GitHub authentication `auth` is non-anonymous and the repository is on
GitHub, the list of contributors to the repository is also collected, after
waiting for `sleep` seconds for each entry.  See
[`PackageAnalyzer.github_auth`](@ref) to obtain a GitHub authentication.
"""
function analyze_path!(dest::AbstractString, repo::AbstractString; name="", uuid=UUID(UInt128(0)), subdir="", auth=github_auth(), sleep=0, tree_hash=nothing, version=v"0")
    isdir(dest) || mkpath(dest)
    only_subdir = false
    reachable = try
        # Clone only latest commit on the default branch.  Note: some
        # repositories aren't reachable because the author made them private or
        # deleted them.  In these cases git would ask for username and password,
        # so we close STDIN to prevent git from prompting for username/password.
        # We need to use `detach` to make closing STDIN effective, suggested by
        # @staticfloat.
        if tree_hash === nothing
            run(pipeline(detach(`$(git()) clone -q --depth 1 $(repo) $(dest)`); stdin=devnull, stderr=devnull))
        else
            m = match(r"github.com/(?<user>.*)/(?<repo>.*)\.git", repo)
            if m !== nothing
                @debug "Downloading code via github api"
                github_extract_code!(dest, m[:user], m[:repo], tree_hash; auth)
            else
                @debug "Falling back to full clone"
                tmp = mktempdir()
                run(pipeline(detach(`$(git()) clone -q $(repo) $(tmp)`); stdin=devnull, stderr=devnull))
                Tar.extract(Cmd(`git archive $tree_hash`; dir=tmp), dest)
            end
            # Either way, we've only put the subdir code into `dest`
            only_subdir = true
        end
        true
    catch e
        @debug "Error; maybe unreachable" exception = e
        # The repository may be unreachable
        false
    end
    return reachable ? analyze_path(dest; repo, reachable, subdir, auth, sleep, only_subdir, version) : Package(name, uuid, repo; subdir, version)
end

"""
    analyze!(root, pkg_entries::AbstractVector{<:Tuple{PkgEntry, $AbstractVersion}}; auth::GitHub.Authorization=github_auth(), sleep=0) -> Vector{Package}
    analyze!(root, pkg_entries::AbstractVector{<:PkgEntry}; auth::GitHub.Authorization=github_auth(), sleep=0) -> Vector{Package}

Analyze all packages in the iterable `pkg_entries`, using threads, cloning them to `root`
if a directory with their `uuid` does not already exist.  Returns a
`Vector{Package}`.

Optionally, use pairs `(PkgEntry, $AbstractVersion)` to specify the version numbers, or pass a keyword argument `version`.
The version number may be a `VersionNumber`, or `:dev`, or `:stable`. When pairs are passed, the
keyword argument `version` will be ignored.

If the GitHub authentication is non-anonymous and the repository is on GitHub,
the list of contributors to the repositories is also collected, after waiting
for `sleep` seconds for each entry (useful to avoid getting rate-limited by
GitHub).  See [`PackageAnalyzer.github_auth`](@ref) to obtain a GitHub
authentication.
"""
function analyze!(root, pkg_entries::AbstractVector{<:Tuple{PkgEntry,AbstractVersion}}; auth::GitHub.Authorization=github_auth(), sleep=0, version=nothing)
    inputs = Channel{Tuple{Int,Tuple{PkgEntry,AbstractVersion}}}(length(pkg_entries))
    for (i, r) in enumerate(pkg_entries)
        put!(inputs, (i, r))
    end
    close(inputs)
    outputs = Channel{Tuple{Int,Package}}(length(pkg_entries))
    Threads.foreach(inputs) do (i, r)
        pkg, version = r
        put!(outputs, (i, analyze!(root, pkg; auth, sleep, version)))
    end
    close(outputs)
    return last.(sort!(collect(outputs); by=first))
end

function analyze!(root, pkg_entries::AbstractVector{PkgEntry}; version=:dev, kw...)
    if version ∉ (:dev, :stable)
        throw(ArgumentError("Only `:dev` and `:stable` are allowed as keyword arguments when analyzing multiple packages"))
    end
    pkg_entries = [(pkg, version) for pkg in pkg_entries]
    return analyze!(root, pkg_entries; kw...)
end

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
  * is reachable: true
  * Julia code in `src`: 4758 lines
  * Julia code in `test`: 1566 lines (24.8% of `test` + `src`)
  * documention in `docs`: 998 lines (17.3% of `docs` + `src`)
  * documention in README: 22 lines
  * has license(s) in file: MIT
    * filename: LICENSE.md
    * OSI approved: true
  * number of contributors: 53 (and 0 anonymous contributors)
  * number of commits: 1516
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

function parse_project(dir)
    bad_project = (; name="Invalid Project.toml", uuid=UUID(UInt128(0)), licenses_in_project=String[])
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
    return (; name=project["name"]::String, uuid, licenses_in_project)
end

"""
    analyze(name_or_dir_or_url::AbstractString; repo = "", reachable=true, subdir="", registry=general_registry(), auth::GitHub.Authorization=github_auth(), version::AbstractVersion=:dev)

Analyze the package pointed to by the mandatory argument and return a summary of
its properties.

If `name_or_dir_or_url` is a valid Julia identifier, it is assumed to be the name of a
package available in `registry`.  The function then uses [`find_package`](@ref)
to find its entry in the registry and analyze its content.

If `name_or_dir_or_url` is a filesystem path, analyze the package whose source code is
located at `name_or_dir_or_url`. Optionally `repo` and `reachable` a boolean indicating
whether or not the package is reachable online, since these can't be inferred
from the source code.  The `subdir` keyword arguments indicates the subdirectory
of `dir` under which the Julia package can be found.

Otherwise, `name_or_dir_or_url` is assumed to be a URL. The repository is cloned to a temporary directory
and analyzed.

If the GitHub authentication is non-anonymous and the repository is on GitHub,
the list of contributors to the repository is also collected.  Only the number
of contributors will be shown in the summary.  See
[`PackageAnalyzer.github_auth`](@ref) to obtain a GitHub authentication.

Pass the keyword argument `version` to confgiure which version of the code is analyzed. Options:

* `:dev` to use the latest code in the repository
* `:stable` to use the latest released version of the code, or
* pass a `VersionNumber` to analyze a particular version of the package.

If `version !== :dev`, only the code associated to that version of the package will be downloaded.
That means for packages in subdirectories, top-level information (like CI scripts) may be unavailable.

## Example

You can analyze a package just by its name, whether you have it installed
locally or not:

```julia
julia> analyze("Pluto")
Package Pluto:
  * repo: https://github.com/fonsp/Pluto.jl.git
  * uuid: c3e4b0f8-55cb-11ea-2926-15256bba5781
  * is reachable: true
  * Julia code in `src`: 6896 lines
  * Julia code in `test`: 3682 lines (34.8% of `test` + `src`)
  * documention in `docs`: 0 lines (0.0% of `docs` + `src`)
  * documention in README: 110 lines
  * has license(s) in file: MIT
    * filename: LICENSE
    * OSI approved: true
  * has license(s) in Project.toml: MIT
    * OSI approved: true
  * number of contributors: 73 (and 1 anonymous contributors)
  * number of commits: 940
  * has `docs/make.jl`: false
  * has `test/runtests.jl`: true
  * has continuous integration: true
    * GitHub Actions
```
"""
function analyze(name_or_dir_or_url::AbstractString; repo="", reachable=true, subdir="", registry=general_registry(), auth::GitHub.Authorization=github_auth(), sleep=0, version::AbstractVersion=:dev)
    if Base.isidentifier(name_or_dir_or_url)
        # The argument looks like a package name rather than a directory: find
        # the package in `registry` and analyze it
        return analyze(find_package(name_or_dir_or_url; registry); auth, sleep, version)
    elseif isdir(name_or_dir_or_url)
        # We don't know the version for a pre-existing directory, so set it to `v"0"`.
        return analyze_path(name_or_dir_or_url; repo, reachable, subdir, auth, sleep, version=v"0")
    else
        repo = name_or_dir_or_url
        dest = mktempdir()
        return analyze_path!(dest, repo; subdir, auth, sleep, version)
    end
end

"""
    analyze(m::Module; kwargs...) -> Package

If you want to analyze a package which is already loaded in the current session,
you can simply call `analyze`, which uses `pkgdir` to determine its source code:

```julia
julia> using DataFrames

julia> analyze(DataFrames)
Package DataFrames:
  * repo: 
  * uuid: a93c6f00-e57d-5684-b7b6-d8193f3e46c0
  * is reachable: true
  * Julia code in `src`: 15809 lines
  * Julia code in `test`: 17512 lines (52.6% of `test` + `src`)
  * documention in `docs`: 3885 lines (19.7% of `docs` + `src`)
  * documention in README: 21 lines
  * has license(s) in file: MIT
    * filename: LICENSE.md
    * OSI approved: true
  * has `docs/make.jl`: true
  * has `test/runtests.jl`: true
  * has continuous integration: true
    * GitHub Actions
```
"""
analyze(m::Module; kwargs...) = analyze_path(pkgdir(m); kwargs...)

function match_pkg(uuid, version, registries)
    for r in registries
        haskey(r.pkgs, uuid) || continue
        # Ok the registry has the package. Does it have the version we need?
        pkg = r.pkgs[uuid]
        info = registry_info(pkg)
        haskey(info.version_info, version) || continue
        # Yes it does
        return pkg
    end
    return nothing
end

function find_packages_in_manifest(path_to_manifest; registries=reachable_registries())
    manifest = TOML.parsefile(path_to_manifest)
    format = parse(VersionNumber, get(manifest, "manifest_format", "1.0"))
    if format.major == 2
        pkgs = manifest["deps"]
    elseif format.major == 1
        pkgs = manifest
    else
        error("Unsupported Manifest format $format")
    end
    results = Tuple{PkgEntry,AbstractVersion}[]
    for (name, list) in pkgs
        for manifest_entry in list
            uuid = UUID(manifest_entry["uuid"]::String)
            if uuid in keys(STDLIBS)
                continue
            end
            version = VersionNumber(manifest_entry["version"]::String)
            pkg = match_pkg(uuid, version, registries)
            if pkg === nothing
                @error("Could not find (package, version) pair in any registry!", name, uuid, version)
            else
                push!(results, (pkg, version))
            end
        end
    end
    return results
end


"""
    analyze_path(dir::AbstractString; repo = "", reachable=true, subdir="", auth::GitHub.Authorization=github_auth(), sleep=0, only_subdir=false, version=v"0") -> Package

Analyze the package whose source code is located at the local path `dir`.  If
the package's repository is hosted on GitHub and `auth` is a non-anonymous
GitHub authentication, wait for `sleep` seconds before collecting the list of
its contributors.

`only_subdir` indicates that while the package's code does live in a subdirectory of the repo,
`dir` points only to that code and we do not have access to the top-level code. We still pass non-empty `subdir`
in this case, to record the fact that the package does indeed live in a subdirectory.

Pass `version` to store the associated version number. Since this call only has access to files on disk, it does not
know the associated version number in any registry.
"""
function analyze_path(dir::AbstractString; repo="", reachable=true, subdir="", auth::GitHub.Authorization=github_auth(), sleep=0, only_subdir=false, version=v"0")
    # we will look for docs, tests, license, and count lines of code
    # in the `pkgdir`; we will look for CI in the `dir`.
    if only_subdir
        pkgdir = dir
    else
        pkgdir = joinpath(dir, subdir)
    end
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
    # if `only_subdir` is true, and we are indeed in a subdirectory, we'll get the paths wrong here.
    # However, we'll find them w/ correct paths in the next check.
    license_files = only_subdir && !isempty(subdir) ? LicenseTableEltype[] : find_licenses(dir)
    if isdir(pkgdir)
        if !isempty(subdir)
            # Look for licenses at top-level and in the subdirectory
            subdir_licenses_files = [(; license_filename=joinpath(subdir, row.license_filename), row.licenses_found, row.license_file_percent_covered) for row in find_licenses(pkgdir)]
            license_files = [subdir_licenses_files; license_files]
        end
        lines_of_code = count_loc(pkgdir)
    else
        license_files = LicenseTableEltype[]
        lines_of_code = LoCTableEltype[]
    end

    if isdir(pkgdir)
        tree_hash = bytes2hex(Pkg.GitTools.tree_hash(pkgdir))
    else
        tree_hash = ""
    end

    # If the repository is on GitHub and we have a non-anonymous GitHub
    # authentication, get the list of contributors
    contributors = if !(auth isa GitHub.AnonymousAuth) && occursin("github.com", repo)
        Base.sleep(sleep)
        repo_name = replace(replace(repo, r"^https://github\.com/" => ""), r"\.git$" => "")
        contribution_table(repo_name; auth)
    else
        ContributionTableElType[]
    end

    Package(name, uuid, repo; subdir, reachable, docs, runtests, travis, appveyor, cirrus,
        circle, drone, buildkite, azure_pipelines, gitlab_pipeline, github_actions,
        license_files, licenses_in_project, lines_of_code, contributors, version, tree_hash)
end

function contribution_table(repo_name; auth)
    return try
        parse_contributions.(GitHub.contributors(GitHub.Repo(repo_name); auth, params=Dict("anon" => "true"))[1])
    catch e
        @error "Could not obtain contributors for $(repo_name)" exception = (e, catch_backtrace())
        ContributionTableElType[]
    end
end

function parse_contributions(c)
    contrib = c["contributor"]
    if contrib.typ == "Anonymous"
        return (; login=missing, id=missing, contrib.name, type=contrib.typ, contributions=c["contributions"])
    else
        return (; contrib.login, contrib.id, name=missing, type=contrib.typ, contributions=c["contributions"])
    end
end


#####
##### Counting things
#####

count_commits(table) = sum(row.contributions for row in table; init=0)
count_commits(pkg::Package) = count_commits(pkg.contributors)

count_contributors(table; type="User") = count(row.type == type for row in table)
count_contributors(pkg::Package; kwargs...) = count_contributors(pkg.contributors; kwargs...)


count_julia_loc(table, dir) = sum(row.code for row in table if row.directory == dir && row.language == :Julia; init=0)

function count_docs(table, dirs=("docs", "doc"))
    rm_langs = (:TOML, :SVG, :CSS, :Javascript)
    sum(row.code + row.comments for row in table if lowercase(row.directory) in dirs && row.language ∉ rm_langs && row.sublanguage ∉ rm_langs; init=0)
end

count_readme(table) = count_docs(table, ("readme", "readme.md"))

count_julia_loc(pkg::Package, args...) = count_julia_loc(pkg.lines_of_code, args...)
count_docs(pkg::Package, args...) = count_docs(pkg.lines_of_code, args...)
count_readme(pkg::Package, args...) = count_readme(pkg.lines_of_code, args...)

end # module
