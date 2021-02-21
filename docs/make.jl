using Documenter, PackageAnalyzer

DocMeta.setdocmeta!(PackageAnalyzer, :DocTestSetup, :(using PackageAnalyzer); recursive=true)

previous_GKSwstype = get(ENV, "GKSwstype", "")
ENV["GKSwstype"] = "100"

makedocs(
    format = Documenter.HTML(
        prettyurls = true
    ),
    modules = [PackageAnalyzer],
    sitename = "PackageAnalyzer.jl",
    pages = ["Home" => "index.md",
             "API Reference" => "api.md",
             "Saving results" => "serialization.md",
             "A look at the General registry" => "look_at_general.md"]
)

deploydocs(
    repo = "github.com/JuliaEcosystem/PackageAnalyzer.jl.git",
    push_preview=true,
    devbranch = "main",
)

# restore the environmental variable `GKSwstype`.
ENV["GKSwstype"] = previous_GKSwstype;
