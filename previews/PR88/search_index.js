var documenterSearchIndex = {"docs":
[{"location":"api/#API-reference","page":"API Reference","title":"API reference","text":"","category":"section"},{"location":"api/","page":"API Reference","title":"API Reference","text":"Modules = [PackageAnalyzer]","category":"page"},{"location":"api/#PackageAnalyzer.analyze-Tuple{AbstractString}","page":"API Reference","title":"PackageAnalyzer.analyze","text":"analyze(name_or_dir_or_url::AbstractString; registry=general_registry(), auth::GitHub.Authorization=github_auth(), version=nothing)\n\nAnalyze the package pointed to by the mandatory argument and return a summary of its properties.\n\nIf name_or_dir_or_url is a valid Julia identifier, it is assumed to be the name of a\n\npackage available in registry.  The function then uses find_package to find its entry in the registry and analyze the content of its latest registered version (or a different version, if the keyword argument version is supplied).\n\nIf name_or_dir_or_url is a filesystem path, analyze the package whose source code is\n\nlocated at name_or_dir_or_url.\n\nOtherwise, name_or_dir_or_url is assumed to be a URL. The repository is cloned to a temporary directory and analyzed.\n\nIf the GitHub authentication is non-anonymous and the repository is on GitHub, the list of contributors to the repository is also collected.  Only the number of contributors will be shown in the summary.  See PackageAnalyzer.github_auth to obtain a GitHub authentication.\n\nwarning: Warning\nFor packages in subdirectories, top-level information (like CI scripts) is only available when name_or_dir_or_url is a URL, or name_or_dir_or_url is a name and version = :dev. In other cases, the top-level code is not accessible.\n\nExample\n\nYou can analyze a package just by its name, whether you have it installed locally or not:\n\njulia> analyze(\"Pluto\"; version=v\"0.18.0\")\nPackageV1 Pluto:\n  * repo: https://github.com/fonsp/Pluto.jl.git\n  * uuid: c3e4b0f8-55cb-11ea-2926-15256bba5781\n  * version: 0.18.0\n  * is reachable: true\n  * tree hash: db1306745717d127037c5697436b04cfb9d7b3dd\n  * Julia code in `src`: 8337 lines\n  * Julia code in `test`: 5448 lines (39.5% of `test` + `src`)\n  * documention in `docs`: 0 lines (0.0% of `docs` + `src`)\n  * documention in README: 118 lines\n  * has license(s) in file: MIT\n    * filename: LICENSE\n    * OSI approved: true\n  * has license(s) in Project.toml: MIT\n    * OSI approved: true\n  * has `docs/make.jl`: false\n  * has `test/runtests.jl`: true\n  * has continuous integration: true\n    * GitHub Actions\n\n\n\n\n\n\n","category":"method"},{"location":"api/#PackageAnalyzer.analyze-Tuple{Module}","page":"API Reference","title":"PackageAnalyzer.analyze","text":"analyze(m::Module; kwargs...) -> PackageV1\n\nIf you want to analyze a package which is already loaded in the current session, you can simply call analyze, which uses pkgdir to determine its source code:\n\njulia> using DataFrames\n\njulia> analyze(DataFrames)\nPackageV1 DataFrames:\n  * repo:\n  * uuid: a93c6f00-e57d-5684-b7b6-d8193f3e46c0\n  * version: 0.0.0\n  * is reachable: true\n  * tree hash: db2a9cb664fcea7836da4b414c3278d71dd602d2\n  * Julia code in `src`: 15628 lines\n  * Julia code in `test`: 21089 lines (57.4% of `test` + `src`)\n  * documention in `docs`: 6270 lines (28.6% of `docs` + `src`)\n  * documention in README: 21 lines\n  * has license(s) in file: MIT\n    * filename: LICENSE.md\n    * OSI approved: true\n  * has `docs/make.jl`: true\n  * has `test/runtests.jl`: true\n  * has continuous integration: true\n    * GitHub Actions\n\n\n\n\n\n","category":"method"},{"location":"api/#PackageAnalyzer.analyze-Tuple{}","page":"API Reference","title":"PackageAnalyzer.analyze","text":"analyze(; kwargs...) -> PackageV1\n\nIf you have an active Julia project with a package at top-level, then you can simply call analyze() to analyze its code.\n\n\n\n\n\n","category":"method"},{"location":"api/#PackageAnalyzer.analyze_code-Tuple{AbstractString}","page":"API Reference","title":"PackageAnalyzer.analyze_code","text":"analyze_code(dir::AbstractString; repo = \"\", reachable=true, subdir=\"\", auth::GitHub.Authorization=github_auth(), sleep=0, only_subdir=false, version=nothing) -> PackageV1\n\nAnalyze the package whose source code is located at the local path dir.  If the package's repository is hosted on GitHub and auth is a non-anonymous GitHub authentication, wait for sleep seconds before collecting the list of its contributors.\n\nonly_subdir indicates that while the package's code does live in a subdirectory of the repo, dir points only to that code and we do not have access to the top-level code. We still pass non-empty subdir in this case, to record the fact that the package does indeed live in a subdirectory.\n\nPass version to store the associated version number. Since this call only has access to files on disk, it does not know the associated version number in any registry.\n\n\n\n\n\n","category":"method"},{"location":"api/#PackageAnalyzer.analyze_manifest-Tuple","page":"API Reference","title":"PackageAnalyzer.analyze_manifest","text":"analyze_manifest([path_to_manifest]; registries=reachable_registries(),\n                 auth=github_auth(), sleep=0)\n\nConvienence function to run find_packages_in_manifest then analyze on the results. Positional argument path_to_manifest defaults to joinpath(dirname(Base.active_project()), \"Manifest.toml\").\n\n\n\n\n\n","category":"method"},{"location":"api/#PackageAnalyzer.analyze_packages-Tuple{Any}","page":"API Reference","title":"PackageAnalyzer.analyze_packages","text":"analyze_packages(pkg_entries; auth::GitHub.Authorization=github_auth(), sleep=0, root=mktempdir()) -> Vector{PackageV1}\n\nAnalyze all packages in the iterable pkg_entries, using threads, storing their code in root if it needs to be downloaded.  Returns a Vector{PackageV1}.\n\nEach element of pkg_entries should be a valid input to analyze.\n\nIf the GitHub authentication is non-anonymous and the repository is on GitHub, the list of contributors to the repositories is also collected, after waiting for sleep seconds for each entry (useful to avoid getting rate-limited by GitHub).  See PackageAnalyzer.github_auth to obtain a GitHub authentication.\n\n\n\n\n\n","category":"method"},{"location":"api/#PackageAnalyzer.find_package-Tuple{Union{Base.UUID, AbstractString}}","page":"API Reference","title":"PackageAnalyzer.find_package","text":"find_package(name_or_uuid::Union{AbstractString, UUID}; registries=reachable_registries(), version::Union{VersionNumber,Nothing}=nothing, strict=true, warn=true) -> PkgSource\n\nReturns the PkgSource for the package pkg.\n\nregistries: a collection of RegistryInstance to look in\nversion: if nothing, finds the maximum registered version in any registry. Otherwise looks for that version number.\nIf strict is true, errors if the package cannot be found. Otherwise, returns nothing.\nIf warn is true, warns if the package cannot be found.\n\nSee also:  find_packages.\n\n\n\n\n\n","category":"method"},{"location":"api/#PackageAnalyzer.find_packages","page":"API Reference","title":"PackageAnalyzer.find_packages","text":"find_packages(; registries=reachable_registries())) -> Vector{PkgSource}\nfind_packages(names::AbstractString...; registries=reachable_registries()) -> Vector{PkgSource}\nfind_packages(names; registries=reachable_registries()) -> Vector{PkgSource}\n\nFind all packages in the given registry (specified by the registry keyword argument), the General registry by default. Return a vector of PkgSource pointing to to the directories of each package in the registry.\n\nPass a list of package names as the first argument to return the paths corresponding to those packages, or individual package names as separate arguments.\n\n\n\n\n\n","category":"function"},{"location":"api/#PackageAnalyzer.find_packages_in_manifest-Tuple{Any}","page":"API Reference","title":"PackageAnalyzer.find_packages_in_manifest","text":"find_packages_in_manifest([path_to_manifest]; registries=reachable_registries(),\n                          strict=true, warn=true)) -> Vector{PkgSource}\n\nReturns Vector{PkgSource} associated to all of the package/version combinations stored in a Manifest.toml.\n\npath_to_manifest defaults to joinpath(dirname(Base.active_project()), \"Manifest.toml\")\nregistries: a collection of RegistryInstance to look in\nstrict and warn have the same meaning as in find_package.\nStandard libraries are always skipped, without warning or errors.\n\n\n\n\n\n","category":"method"},{"location":"api/#PackageAnalyzer.github_auth","page":"API Reference","title":"PackageAnalyzer.github_auth","text":"PackageAnalyzer.github_auth(token::String=\"\")\n\nObtain a GitHub authetication.  Use the token argument if it is non-empty, otherwise use the GITHUB_TOKEN and GITHUB_AUTH environment variables, if set and of length 40.  If all these methods fail, return an anonymous authentication.\n\n\n\n\n\n","category":"function"},{"location":"serialization/#Saving-results","page":"Saving results","title":"Saving results","text":"","category":"section"},{"location":"serialization/","page":"Saving results","title":"Saving results","text":"PackageAnalyzer uses Legolas.jl to define several schemas to support serialization. These schemas may be updated in backwards-compatible ways in non-breaking releases, by e.g. adding additional optional fields.","category":"page"},{"location":"serialization/","page":"Saving results","title":"Saving results","text":"A table compliant with the package-analyzer.package schema may be serialized with","category":"page"},{"location":"serialization/","page":"Saving results","title":"Saving results","text":"using Legolas\nLegolas.write(io, table, PackageV1SchemaVersion())","category":"page"},{"location":"serialization/","page":"Saving results","title":"Saving results","text":"and read back by","category":"page"},{"location":"serialization/","page":"Saving results","title":"Saving results","text":"io = Legolas.read(io)","category":"page"},{"location":"serialization/","page":"Saving results","title":"Saving results","text":"For example,","category":"page"},{"location":"serialization/","page":"Saving results","title":"Saving results","text":"using DataFrames, Legolas, PackageAnalyzer\nresults = analyze_packages(find_packages(\"DataFrames\", \"Flux\"));\nLegolas.write(\"packages.arrow\", results, PackageV1SchemaVersion())\nroundtripped_results = DataFrame(Arrow.Table(\"packages.arrow\"))\nrm(\"packages.arrow\") # hide","category":"page"},{"location":"#PackageAnalyzer.jl","page":"Home","title":"PackageAnalyzer.jl","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"The main functionality of the package is the analyze function:","category":"page"},{"location":"","page":"Home","title":"Home","text":"julia> using PackageAnalyzer\n\njulia> analyze(\"Flux\")\nPackageV1 Flux:\n  * repo: https://github.com/FluxML/Flux.jl.git\n  * uuid: 587475ba-b771-5e3f-ad9e-33799f191a9c\n  * version: 0.13.6\n  * is reachable: true\n  * tree hash: 76ca02c7c0cb7b8337f7d2d0eadb46ed03c1e843\n  * Julia code in `src`: 5299 lines\n  * Julia code in `test`: 3030 lines (36.4% of `test` + `src`)\n  * documentation in `docs`: 1856 lines (25.9% of `docs` + `src`)\n  * documentation in README: 14 lines\n  * has license(s) in file: MIT\n    * filename: LICENSE.md\n    * OSI approved: true\n  * has `docs/make.jl`: true\n  * has `test/runtests.jl`: true\n  * has continuous integration: true\n    * GitHub Actions\n    * Buildkite","category":"page"},{"location":"","page":"Home","title":"Home","text":"The argument is a string, which can be the name of a package, a local path or a URL.","category":"page"},{"location":"","page":"Home","title":"Home","text":"NOTE: the Git repository of the package may be cloned, in order to inspect its content.","category":"page"},{"location":"","page":"Home","title":"Home","text":"You can also pass the output of find_package which is used under-the-hood to look up package names in any installed registries. find_package also allows one to specify a package by UUID.","category":"page"},{"location":"","page":"Home","title":"Home","text":"julia> analyze(find_package(\"JuMP\"; version=v\"1\"))\nPackageV1 JuMP:\n  * repo: https://github.com/jump-dev/JuMP.jl.git\n  * uuid: 4076af6c-e467-56ae-b986-b466b2749572\n  * version: 1.0.0\n  * is reachable: true\n  * tree hash: 936e7ebf6c84f0c0202b83bb22461f4ebc5c9969\n  * Julia code in `src`: 16906 lines\n  * Julia code in `test`: 12777 lines (43.0% of `test` + `src`)\n  * documentation in `docs`: 15978 lines (48.6% of `docs` + `src`)\n  * documentation in README: 79 lines\n  * has license(s) in file: MPL-2.0\n    * filename: LICENSE.md\n    * OSI approved: true\n  * has `docs/make.jl`: true\n  * has `test/runtests.jl`: true\n  * has continuous integration: true\n    * GitHub Actions","category":"page"},{"location":"","page":"Home","title":"Home","text":"Additionally, you can pass in the module itself:","category":"page"},{"location":"","page":"Home","title":"Home","text":"julia> using PackageAnalyzer\n\njulia> analyze(PackageAnalyzer)\nPackageV1 PackageAnalyzer:\n  * repo:\n  * uuid: e713c705-17e4-4cec-abe0-95bf5bf3e10c\n  * version: nothing\n  * is reachable: true\n  * tree hash: 7bfd2ab7049d92809eb18eed1b0548c7e07ec150\n  * Julia code in `src`: 912 lines\n  * Julia code in `test`: 276 lines (23.2% of `test` + `src`)\n  * documentation in `docs`: 263 lines (22.4% of `docs` + `src`)\n  * documentation in README: 44 lines\n  * has license(s) in file: MIT\n    * filename: LICENSE\n    * OSI approved: true\n  * has `docs/make.jl`: true\n  * has `test/runtests.jl`: true\n  * has continuous integration: true\n    * GitHub Actions","category":"page"},{"location":"","page":"Home","title":"Home","text":"You can also directly analyze the source code of a package via analyze by passing in the path to it, for example with the pkgdir function:","category":"page"},{"location":"","page":"Home","title":"Home","text":"julia> using PackageAnalyzer, DataFrames\n\njulia> analyze(pkgdir(DataFrames))\nPackageV1 DataFrames:\n  * repo:\n  * uuid: a93c6f00-e57d-5684-b7b6-d8193f3e46c0\n  * version: 0.0.0\n  * is reachable: true\n  * tree hash: db2a9cb664fcea7836da4b414c3278d71dd602d2\n  * Julia code in `src`: 15628 lines\n  * Julia code in `test`: 21089 lines (57.4% of `test` + `src`)\n  * documentation in `docs`: 6270 lines (28.6% of `docs` + `src`)\n  * documentation in README: 21 lines\n  * has license(s) in file: MIT\n    * filename: LICENSE.md\n    * OSI approved: true\n  * has `docs/make.jl`: true\n  * has `test/runtests.jl`: true\n  * has continuous integration: true\n    * GitHub Actions","category":"page"},{"location":"","page":"Home","title":"Home","text":"You can pass the keyword argument root to specify a directory to store downloaded code.","category":"page"},{"location":"#The-PackageV1-struct","page":"Home","title":"The PackageV1 struct","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"The returned values from analyze, and analyze! are objects of the type PackageV1, which has the following fields:","category":"page"},{"location":"","page":"Home","title":"Home","text":"struct PackageV1\n    name::String # name of the package\n    uuid::UUID # uuid of the package\n    repo::String # URL of the repository\n    subdir::String # subdirectory of the package in the repo\n    reachable::Bool # can the repository be cloned?\n    docs::Bool # does it have documentation?\n    runtests::Bool # does it have the test/runtests.jl file?\n    github_actions::Bool # does it use GitHub Actions?\n    travis::Bool # does it use Travis CI?\n    appveyor::Bool # does it use AppVeyor?\n    cirrus::Bool # does it use Cirrus CI?\n    circle::Bool # does it use Circle CI?\n    drone::Bool # does it use Drone CI?\n    buildkite::Bool # does it use Buildkite?\n    azure_pipelines::Bool # does it use Azure Pipelines?\n    gitlab_pipeline::Bool # does it use Gitlab Pipeline?\n    license_files::Vector{LicenseV1} # a table of all possible license files\n    licenses_in_project::Vector{String} # any licenses in the `license` key of the Project.toml\n    lines_of_code::Vector{LinesOfCodeV2} # table of lines of code\n    contributors::Vector{ContributorsV1} # table of contributor data\n    version::Union{String, Missing} # the version number, if a release was analyzed\n    tree_hash::String # the tree hash of the code that was analyzed\nend","category":"page"},{"location":"","page":"Home","title":"Home","text":"where:","category":"page"},{"location":"","page":"Home","title":"Home","text":"LicenseV1 contains fields license_filename::String, licenses_found::Vector{String}, license_file_percent_covered::Float64,\nLinesOfCodeV2 contains fields directory::String, language::Symbol, sublanguage::Union{Nothing, Symbol}, files::Int, code::Int, comments::Int, blanks::Int,\nand ContributorsV1 contains fields login::Union{String,Missing}, id::Union{Int,Missing}, name::Union{String,Missing}, type::String, contributions::Int.","category":"page"},{"location":"","page":"Home","title":"Home","text":"Adding additional fields to PackageV1 is not considered breaking, and may occur in feature releases of PackageAnalyzer.jl.","category":"page"},{"location":"","page":"Home","title":"Home","text":"Removing or altering the meaning of existing fields is considered breaking and will only occur in major releases of PackageAnalyzer.jl.","category":"page"},{"location":"#Analyzing-multiple-packages","page":"Home","title":"Analyzing multiple packages","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"To run the analysis for multiple packages you can either use broadcasting","category":"page"},{"location":"","page":"Home","title":"Home","text":"analyze.(pkg_entries)","category":"page"},{"location":"","page":"Home","title":"Home","text":"or use the function analyze_packages(pkg_entries) which runs the analysis with multiple threads. Here, pkg_entries may be any valid input to analyze.","category":"page"},{"location":"","page":"Home","title":"Home","text":"You can use the function find_packages to find all packages in a given registry:","category":"page"},{"location":"","page":"Home","title":"Home","text":"julia> result = find_packages(; registry=general_registry());\n\njulia> summary(result)\n\"7213-element Vector{PkgSource}\"","category":"page"},{"location":"","page":"Home","title":"Home","text":"Do not abuse this function!","category":"page"},{"location":"","page":"Home","title":"Home","text":"warning: Warning\nCloning all the repos in General will take more than 20 GB of disk space and can take up to a few hours to complete.","category":"page"},{"location":"","page":"Home","title":"Home","text":"You can also use find_packages_in_manifest to use a Manifest.toml to lookup packages and their versions. Besides handling release dependencies, this should also correctly handle dev'd dependencies, and non-released Pkg.add'd dependencies. The helper analyze_manifest is provided as a convenience to composing find_packages_in_manifest and analyze_packages.","category":"page"},{"location":"#License-information","page":"Home","title":"License information","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"The license_files field of the PackageV1 object is a Tables.jl row table containing much more detailed information about any or all files containing licenses, identified by licensecheck via LicenseCheck.jl. For example, RandomProjectionTree.jl is dual licensed under both Apache-2.0 and the MIT license, and provides two separate license files. Interestingly, the README is also identified as containing an Apache-2.0 license; I've filed an issue to see if this is intentional.","category":"page"},{"location":"","page":"Home","title":"Home","text":"julia> using PackageAnalyzer, DataFrames\n\njulia> result = analyze(\"RandomProjectionTree\");\n\njulia> DataFrame(result.license_files)\n3×3 DataFrame\n Row │ license_filename  licenses_found  license_file_percent_covered\n     │ String            Vector{String}  Float64\n─────┼────────────────────────────────────────────────────────────────\n   1 │ LICENSE-APACHE    [\"Apache-2.0\"]                     100.0\n   2 │ LICENSE-MIT       [\"MIT\"]                            100.0\n   3 │ README.md         [\"Apache-2.0\"]                       6.34921","category":"page"},{"location":"","page":"Home","title":"Home","text":"Most packages contain a single file containing a license, and so have a single entry in the table.","category":"page"},{"location":"#Lines-of-code","page":"Home","title":"Lines of code","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"The lines_of_code field of the PackageV1 object is a Tables.jl row table containing much more detailed information about the lines of code count (thanks to tokei) and can e.g. be passed to a DataFrame for further analysis.","category":"page"},{"location":"","page":"Home","title":"Home","text":"julia> using PackageAnalyzer, DataFrames\n\njulia> result = analyze(pkgdir(DataFrames));\n\njulia> DataFrame(result.lines_of_code)\n15×7 DataFrame\n Row │ directory        language  sublanguage  files  code   comments  blanks\n     │ String           Symbol    Union…       Int64  Int64  Int64     Int64\n─────┼────────────────────────────────────────────────────────────────────────\n   1 │ test             Julia                     29  17512       359    2264\n   2 │ src              Julia                     31  15809       885    1253\n   3 │ benchmarks       Julia                      4    245        30      50\n   4 │ benchmarks       Shell                      2     15         0       0\n   5 │ docs             Julia                      1     45         6       5\n   6 │ docs             TOML                       1     11         0       1\n   7 │ docs             Markdown                  16      0      3782     662\n   8 │ docs             Markdown  Julia            4     30         3       4\n   9 │ docs             Markdown  Python           1     13         0       1\n  10 │ docs             Markdown  R                1      6         0       0\n  11 │ Project.toml     TOML                       1     51         0       4\n  12 │ README.md        Markdown                   1      0        21      10\n  13 │ NEWS.md          Markdown                   1      0       267      47\n  14 │ LICENSE.md       Markdown                   1      0        22       1\n  15 │ CONTRIBUTING.md  Markdown                   1      0       138      20","category":"page"},{"location":"#Contributors-to-the-repository","page":"Home","title":"Contributors to the repository","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"If the package repository is hosted on GitHub and you can use GitHub authentication, the list of contributors is added to the contributors field of the PackageV1 object.  This is a table which includes the GitHub username (\"login\") and the GitHub ID (\"id\") for contributors identified as GitHub \"users\", and the \"name\" for contributors identified as \"Anonymous\" contributors, as well as the number of contributions provided by that user to the repository. This is the data returned from the GitHub API, and there may be people for which some of their contributions are marked as from an anonymous user (possibly more than one!) and some of their contributions are associated to their GitHub username.","category":"page"},{"location":"","page":"Home","title":"Home","text":"julia> using PackageAnalyzer, DataFrames\n\njulia> result = analyze(\"DataFrames\");\n\njulia> df = DataFrame(result.contributors);\n\njulia> sort!(df, :contributions, rev=true)\n189×5 DataFrame\n Row │ login                id        name           type       contributions\n     │ String?              Int64?    String?        String     Int64\n─────┼────────────────────────────────────────────────────────────────────────\n   1 │ johnmyleswhite          22064  missing        User                 431\n   2 │ bkamins               6187170  missing        User                 412\n   3 │ powerdistribution     5247292  missing        User                 232\n   4 │ nalimilan             1120448  missing        User                 223\n   5 │ garborg               2823840  missing        User                 173\n   6 │ quinnj                2896623  missing        User                 104\n   7 │ simonster              470884  missing        User                  87\n   8 │ missing               missing  Harlan Harris  Anonymous             67\n   9 │ cjprybol              3497642  missing        User                  50\n  10 │ alyst                  348591  missing        User                  48\n  11 │ dmbates                371258  missing        User                  47\n  12 │ tshort                 636420  missing        User                  39\n  13 │ doobwa                  79467  missing        User                  32\n  14 │ HarlanH                130809  missing        User                  32\n  15 │ kmsquire               223250  missing        User                  30\n  ⋮  │          ⋮              ⋮            ⋮            ⋮            ⋮","category":"page"},{"location":"#GitHub-authentication","page":"Home","title":"GitHub authentication","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"If you have a GitHub Personal Access Token, you can obtain some extra information about packages whose repository is hosted on GitHub (e.g. the list of contributors).  If you store the token as an environment variable called GITHUB_TOKEN or GITHUB_AUTH, this will be automatically used whenever possible, otherwise you can generate a GitHub authentication with the PackageAnalyzer.github_auth function and pass it to the functions accepting the auth::GitHub.Authorization keyword argument.","category":"page"}]
}
