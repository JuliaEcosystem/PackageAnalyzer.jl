#####
##### GitHub things
#####

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

function github_extract_code!(dest::AbstractString, user::AbstractString, repo::AbstractString, tree_hash::AbstractString; auth)
    # GitHub allows one to directly HTTP GET a URL like:
    # https://github.com/$(user)/$(repo)/archive/tarball/$(tree_hash)
    # But we go through `GitHub.gh_get` so we can easily use our auth token `auth`,
    # in particular to support private packages.
    # Note: GitHub does *not* support the `git archive` protocol, so we cannot just do a remote `git archive`.
    path = "/repos/$(user)/$(repo)/tarball/$(tree_hash)"
    resp = GitHub.gh_get(GitHub.DEFAULT_API, path; auth)
    tmp = mktempdir()
    Tar.extract(GzipDecompressorStream(IOBuffer(resp.body)), tmp)
    files = only(readdir(tmp; join=true))
    isdir(dest) || mkdir(dest)
    mv(files, dest; force=true)
    return nothing
end


#####
##### Parsing things
#####

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


function contribution_table(repo_name; auth)
    return @maybecatch begin
        parse_contributions.(GitHub.contributors(GitHub.Repo(repo_name); auth, params=Dict("anon" => "true"))[1])
    end "Could not obtain contributors for $(repo_name)" ContributionsV1[]
end

function parse_contributions(c)
    contrib = c["contributor"]
    if contrib.typ == "Anonymous"
        return ContributionsV1(; contrib.name, type=contrib.typ, contributions=c["contributions"])
    else
        return ContributionsV1(; contrib.login, contrib.id, type=contrib.typ, contributions=c["contributions"])
    end
end

#####
##### RegistryInstances thread safety
#####

# RegistryInstances uses LazilyInitializedFields, and if we try to initialize a field
# from two different threads, we have a data-race. We'll add a lock for these.

const REGISTRY_UUID_LOCK = ReentrantLock()

function get_uuids(name::AbstractString, registry)
    return Base.@lock REGISTRY_UUID_LOCK begin
        RegistryInstances.uuids_from_name(registry, name)
    end
end

function get_uuids(uuid::UUID, registry)
    return haskey(registry.pkgs, uuid) ? [uuid] : UUID[]
end

const REGISTRY_INFO_LOCK = ReentrantLock()

function registry_info(pkg::PkgEntry)
    return Base.@lock REGISTRY_INFO_LOCK begin
        RegistryInstances.registry_info(pkg)
    end
end


#####
##### Other
#####

# Don't error if licensecheck isn't working, just log it
function _find_licenses(dir)
    @maybecatch(LicenseV1.(find_licenses(dir)), "Error finding licenses in $dir", LicenseV1[])
end

function get_tree_hash(dir::AbstractString)
    return bytes2hex(Pkg.GitTools.tree_hash(dir))
end

function git()
    use_local_env = Base.parse(Bool, get(ENV,"USE_LOCAL_GIT", "false"))
    # Git.jl has issues on MacOS, so if we have a local git there, use it,
    # Also allow ENV-based opt-out. Why? Not sure about private packages.
    if use_local_env || (Sys.isapple() && Sys.which("git") !== nothing)
        return `git`
    else
        Git.git()
    end
end
