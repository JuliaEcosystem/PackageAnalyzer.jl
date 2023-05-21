# `obtain_code`: PkgSource -> (local_path, reachable, version)

function obtain_code(dev::Dev; root=nothing, auth=nothing)
    return (dev.path, true, nothing, "")
end

function obtain_code(trunk::Trunk; root=mktempdir(), auth=nothing)
    # Clone from URL and store in root
    # We always store in a tempdir bc we will need to reclone
    # anyway, since we are asking for latest release.
    dest = mktempdir(root)
    reachable = download_latest_code(dest, trunk.repo_url)
    return (dest, reachable, nothing, trunk.subdir)
end

function obtain_code(added::Added; root=mktempdir(), auth=github_auth())
    tree_hash = added.tree_hash
    # use either path OR repo url + tree-hash
    sha = Base.SHA1(hex2bytes(tree_hash))
    vs = Base.version_slug(added.uuid, sha)
    dest = joinpath(root, added.name, vs)

    if !isempty(added.repo_url)
        reachable = download_tree_hash(dest, added.repo_url; tree_hash, auth)
    else
        # Extract from local git repo
        reachable = @maybecatch begin
            Tar.extract(Cmd(`$(git()) archive $tree_hash`; dir=added.path), dest)
            true
        end "Error extracting archive from local git repo" false
    end

    if reachable && get_tree_hash(dest) != tree_hash
        @debug "Must be download corruption; tree hash of download does not match expected" get_tree_hash(dest) tree_hash
        reachable = false
    end
    return (dest, reachable, nothing, "")
end


function obtain_code(release::Release; root=mktempdir(), auth=github_auth())
    version = release.version
    tree_hash = release.tree_hash

    vs = Base.version_slug(release.uuid, Base.SHA1(hex2bytes(tree_hash)))
    tail = joinpath(release.name, vs)

    # Since it's a release, the user may have it installed already
    # Since we have hashes, we can verify it's the right code
    for d in Pkg.depots()
        path = joinpath(d, "packages", tail)
        isdir(path) || continue
        path_tree_hash = get_tree_hash(path)
        if path_tree_hash == tree_hash
            @debug "Found installed path at `$(path)`! Using that"
            return (path, true, version, "")
        end
    end

    # Check if we can skip the download
    dest = joinpath(root, tail)
    if isdir(dest)
        dest_tree_hash = get_tree_hash(dest)
        if dest_tree_hash == tree_hash
            @debug "Found existing download at $(dest)!"
            return (dest, true, version, "")
        end
    end

    repo = release.repo
    if repo === nothing
        error("Package $(release.name) does not have assocaiated repo URL in registry at $(release.registry_path)")
    end
    reachable = download_tree_hash(dest, repo; tree_hash, auth)

    if reachable && get_tree_hash(dest) != tree_hash
        @debug "Must be download corruption; tree hash of download does not match expected" get_tree_hash(dest) tree_hash
        reachable = false
    end
    return (dest, reachable, version, "")
end


function download_latest_code(dest::AbstractString, repo::AbstractString)
    isdir(dest) || mkpath(dest)
    @debug "Downloading code from $repo to $dest"
    reachable = @maybecatch begin
        # Clone only latest commit on the default branch.  Note: some
        # repositories aren't reachable because the author made them private or
        # deleted them.  In these cases git would ask for username and password,
        # so we close STDIN to prevent git from prompting for username/password.
        # We need to use `detach` to make closing STDIN effective, suggested by
        # @staticfloat.
        run(pipeline(detach(`$(git()) clone -q --depth 1 $(repo) $(dest)`); stdin=devnull, stderr=devnull))
        true
    end "Error downloading code; maybe unreachable" false
    return reachable
end

function download_tree_hash(dest, repo; tree_hash, auth=github_auth())
    isdir(dest) || mkpath(dest)
    # First, try to use the github API
    reachable = @maybecatch begin
        m = match(r"github.com/(?<user>.*)/(?<repo>.*)\.git", repo)
        if m !== nothing
            @debug "Downloading code via github api"
            # These extra `AbstractString` type assertions make JET happy.
            github_extract_code!(dest, m[:user]::AbstractString, m[:repo]::AbstractString, tree_hash; auth)
            true
        else
            # We can't, doesn't look like a git repo
            false
        end
    end "Error downloading from github API; maybe unreachable" false
    reachable && return reachable
    # OK, that didn't work, let's try cloning.
    reachable = @maybecatch begin
        @debug "Falling back to full clone"
        tmp = mktempdir()
        run(pipeline(detach(`$(git()) clone -q $(repo) $(tmp)`); stdin=devnull, stderr=devnull))
        Tar.extract(Cmd(`$(git()) archive $tree_hash`; dir=tmp), dest)
        true
    end "Error performing git clone; maybe unreachable"  false
    return reachable
end
