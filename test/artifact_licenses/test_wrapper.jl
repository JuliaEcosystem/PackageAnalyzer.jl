function with_active_manifest(f::Function)
    original_project = Base.active_project()
    mktempdir() do tmp_project_dir
        cd(tmp_project_dir) do
            # For the `artifact_licenses` tests, we check a test manifest into source control.
            # Otherwise, our tests can easily break if a JLL package is added or removed
            # as an indirect dependency.

            src_proj = joinpath(@__DIR__, "Project.toml")
            dst_proj = joinpath(tmp_project_dir, "Project.toml")
            cp(src_proj, dst_proj)

            # Older versions of Julia don't support versioned manifest names, so just to
            # be safe, we rename our selected manifest to `Manifest.toml`, which is a manifest
            # name that we know will work on all Julia versions.
            src_man = joinpath(@__DIR__, "Manifest-v$(VERSION.major).$(VERSION.minor).toml")
            dst_man = joinpath(tmp_project_dir, "Manifest.toml")
            cp(src_man, dst_man)

            try
                Pkg.activate(tmp_project_dir)
                Pkg.instantiate()
                Pkg.precompile()
                f()
            finally
                Pkg.activate(original_project)
            end
        end
    end
end

with_active_manifest() do
    include("test_main.jl")
end
