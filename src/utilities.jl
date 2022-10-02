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

