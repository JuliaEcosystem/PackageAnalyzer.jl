using Documenter, PackageAnalyzer

DocMeta.setdocmeta!(PackageAnalyzer, :DocTestSetup, :(using PackageAnalyzer); recursive=true)

makedocs(
    format = Documenter.HTML(
        prettyurls = true
    ),
    modules = [PackageAnalyzer],
    sitename = "PackageAnalyzer.jl",
    pages = ["Home" => "index.md",
             "API Reference" => "api.md",
             "Saving results" => "serialization.md"]
)

deploydocs(
    repo = "github.com/JuliaEcosystem/PackageAnalyzer.jl.git",
    push_preview=true,
    devbranch = "main",
)
