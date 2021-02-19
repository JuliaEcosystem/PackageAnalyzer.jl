using Documenter, AnalyzeRegistry

DocMeta.setdocmeta!(AnalyzeRegistry, :DocTestSetup, :(using AnalyzeRegistry); recursive=true)

makedocs(
    format = Documenter.HTML(
        prettyurls = true
    ),
    modules = [AnalyzeRegistry],
    sitename = "AnalyzeRegistry.jl",
    pages = ["Home" => "index.md",
             "API Reference" => "api.md",
             "Saving results" => "serialization.md"]
)

deploydocs(
    repo = "github.com/giordano/AnalyzeRegistry.jl.git",
    push_preview=true,
    devbranch = "main",
)
