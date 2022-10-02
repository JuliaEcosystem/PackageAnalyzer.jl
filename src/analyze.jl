#####
##### Entrypoints
#####

# These functions take in user-friendly strings / URLs / modules,
# and call `analyze` or `analyze_packages` with `PkgSource`'s.

"""
    analyze(name_or_dir_or_url::AbstractString; registry=general_registry(), auth::GitHub.Authorization=github_auth(), version=nothing)

Analyze the package pointed to by the mandatory argument and return a summary of
its properties.

* If `name_or_dir_or_url` is a valid Julia identifier, it is assumed to be the name of a
package available in `registry`.  The function then uses [`find_package`](@ref)
to find its entry in the registry and analyze the content of its latest registered version (or a different version, if the keyword argument `version` is supplied).
* If `name_or_dir_or_url` is a filesystem path, analyze the package whose source code is
located at `name_or_dir_or_url`.
* Otherwise, `name_or_dir_or_url` is assumed to be a URL. The repository is cloned to a temporary directory and analyzed.

If the GitHub authentication is non-anonymous and the repository is on GitHub,
the list of contributors to the repository is also collected.  Only the number
of contributors will be shown in the summary.  See
[`PackageAnalyzer.github_auth`](@ref) to obtain a GitHub authentication.

!!! warning
    For packages in subdirectories, top-level information (like CI scripts) is only available when `name_or_dir_or_url` is a URL, or `name_or_dir_or_url` is a name and `version = :dev`. In other cases, the top-level code is not accessible.

## Example

You can analyze a package just by its name, whether you have it installed
locally or not:

```julia
julia> analyze("Pluto"; version=v"0.18.0")
Package Pluto:
  * repo: https://github.com/fonsp/Pluto.jl.git
  * uuid: c3e4b0f8-55cb-11ea-2926-15256bba5781
  * version: 0.18.0
  * is reachable: true
  * tree hash: db1306745717d127037c5697436b04cfb9d7b3dd
  * Julia code in `src`: 8337 lines
  * Julia code in `test`: 5448 lines (39.5% of `test` + `src`)
  * documention in `docs`: 0 lines (0.0% of `docs` + `src`)
  * documention in README: 118 lines
  * has license(s) in file: MIT
    * filename: LICENSE
    * OSI approved: true
  * has license(s) in Project.toml: MIT
    * OSI approved: true
  * has `docs/make.jl`: false
  * has `test/runtests.jl`: true
  * has continuous integration: true
    * GitHub Actions

```
"""
function analyze(name_or_dir_or_url::AbstractString; registries=reachable_registries(), auth::GitHub.Authorization=github_auth(), sleep=0, version=nothing, root=mktempdir(), subdir="")
    if Base.isidentifier(name_or_dir_or_url)
        if !isempty(subdir)
            error()
        end
        # The argument looks like a package name rather than a directory: find
        # the package in `registry` and analyze it
        version = something(version, :stable) # default to stable
        release = find_package(name_or_dir_or_url; registries, version)
        return analyze(release; auth, sleep, root)
    elseif isdir(name_or_dir_or_url)
        if !isempty(subdir)
            error()
        end
        # Local directory
        if version !== nothing
            error("Passing a `version` is unsupported for local directories.")
        end
        return analyze(Dev(; path=name_or_dir_or_url); auth, sleep, root)
    else
        # Remote URL
        if version !== nothing
            error("Passing a `version` is unsupported for remote URLs.")
        end
        return analyze(Trunk(; repo_url=name_or_dir_or_url, subdir); auth, sleep, root)
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
  * version: 0.0.0
  * is reachable: true
  * tree hash: db2a9cb664fcea7836da4b414c3278d71dd602d2
  * Julia code in `src`: 15628 lines
  * Julia code in `test`: 21089 lines (57.4% of `test` + `src`)
  * documention in `docs`: 6270 lines (28.6% of `docs` + `src`)
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
analyze(m::Module; kwargs...) = analyze(Dev(; path=pkgdir(m)); kwargs...)


"""
    analyze_manifest([path_to_manifest]; registries=reachable_registries(),
                     auth=github_auth(), sleep=0)

Convienence function to run [`find_packages_in_manifest`](@ref) then [`analyze`](@ref) on the results. Positional argument `path_to_manifest` defaults to `joinpath(dirname(Base.active_project()), "Manifest.toml")`.
"""
function analyze_manifest(args...; registries=reachable_registries(),
                          auth=github_auth(), sleep=0)
    pkgs = find_packages_in_manifest(args...; registries)
    return analyze_packages(pkgs; auth, sleep)
end

#####
##### analyze(::PkgSource)
#####

# Here, we lower commands one step further to `analyze_code`

function analyze(pkg::Release; root=mktempdir(), auth=github_auth(), sleep=0)
    local_dir, reachable, version, _ = obtain_code(pkg; root, auth)
    info = registry_info(pkg.entry)
    repo = something(info.repo, "")
    subdir = something(info.subdir, "")
    if !reachable
        return Package(pkg.entry.name, pkg.entry.uuid, repo; reachable, subdir, version)
    end
    only_subdir = true
    return analyze_code(local_dir; auth, subdir, reachable, only_subdir, repo, sleep, version)
end

function analyze(pkg::Added; root=mktempdir(), auth=github_auth(), sleep=0)
    local_dir, reachable, version, _ = obtain_code(pkg; root, auth)
    subdir = something(pkg.subdir, "")
    repo = something(pkg.repo_url, "")
    if !reachable
        return Package(pkg.name, pkg.uuid, repo; reachable, subdir, version)
    end
    only_subdir = true
    return analyze_code(local_dir; auth, subdir, reachable, only_subdir, repo, sleep, version)
end

function analyze(pkg::Dev; root=mktempdir(), auth=github_auth(), sleep=0)
    local_dir, reachable, version, _ = obtain_code(pkg; root, auth)
    subdir = ""
    repo = ""
    if !reachable
        return Package(pkg.name, pkg.uuid, repo; reachable, subdir, version)
    end
    only_subdir = true
    return analyze_code(local_dir; auth, subdir, reachable, only_subdir, repo, sleep, version)
end

function analyze(pkg::Trunk; root=mktempdir(), auth=github_auth(), sleep=0)
    local_dir, reachable, version, subdir = obtain_code(pkg; root, auth)
    repo = pkg.repo_url
    if !reachable
        return Package(pkg.name, pkg.uuid, repo; reachable, subdir, version)
    end
    only_subdir = false
    return analyze_code(local_dir; auth, subdir, reachable, only_subdir, repo, sleep, version)
end


#####
##### `analyze_code`
#####

# Here we analyze a local directory.
# This is an internal function.

"""
    analyze_code(dir::AbstractString; repo = "", reachable=true, subdir="", auth::GitHub.Authorization=github_auth(), sleep=0, only_subdir=false, version=nothing) -> Package

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
function analyze_code(dir::AbstractString; repo="", reachable=true, subdir="", auth::GitHub.Authorization=github_auth(), sleep=0, only_subdir=false, version=nothing)
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
    license_files = only_subdir && !isempty(subdir) ? LicenseTableEltype[] : _find_licenses(dir)
    if isdir(pkgdir)
        if !isempty(subdir)
            # Look for licenses at top-level and in the subdirectory
            subdir_licenses_files = [(; license_filename=joinpath(subdir, row.license_filename), row.licenses_found, row.license_file_percent_covered) for row in _find_licenses(pkgdir)]
            license_files = [subdir_licenses_files; license_files]
        end
        lines_of_code = count_loc(pkgdir)
    else
        license_files = LicenseTableEltype[]
        lines_of_code = LoCTableEltype[]
    end

    if isdir(pkgdir)
        tree_hash = get_tree_hash(pkgdir)
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
