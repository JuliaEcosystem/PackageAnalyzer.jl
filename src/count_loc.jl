#####
##### Entrypoint & helpers
#####
using JuliaSyntax: SourceFile

# Entrypoint
function count_loc(dir)
    # we pass `dir` to the command object so that we get relative paths in the `tokei` output.
    # This makes it easy to process later, since we have uniform filepaths
    json = try
        JSON3.read(read(Cmd(`$(tokei()) --output json .`; dir)))
    catch e
        @error "`tokei` error: " exception = e maxlog = 2
        missing
    end
    table = make_loc_table(json)
    # Filter out `Julia`, since we will parse that ourselves
    filter!(table) do row
        row.language !== :Julia
    end
    append!(table, count_julia_loc(dir))
    return table
end

function make_loc_table(json)
    table = LoCTableEltype[]
    ismissing(json) && return table
    for (language, language_loc) in pairs(json)
        # we want to count lines of code per toplevel directory, per language, and per sublanguage (e.g. for Julia inside of Markdown)
        counts = Dict{@NamedTuple{directory::String, sublanguage::Union{Nothing,Symbol}},@NamedTuple{files::Int, code::Int, comments::Int, docstrings::Int, blanks::Int}}()
        language == :Total && continue # skip the fake `Total` language
        language_loc.inaccurate && continue # skip if it's marked `inaccurate` (not sure when that happens?)
        for report in language_loc.reports
            # `splitpath(relative_path)[1] == ".", so `splitpath(relative_path)[2]` gives us the toplevel directory or filename
            directory = splitpath(report.name)[2]
            loc_update!(counts, (; directory, sublanguage=nothing), report.stats)
            for (sublanguage, sublanguage_loc) in report.stats.blobs
                loc_update!(counts, (; directory, sublanguage), sublanguage_loc)
            end
        end
        for ((directory, sublanguage), count) in pairs(counts)
            push!(table, (; directory, language, sublanguage, count.files, count.code, count.comments, docstrings=0, count.blanks))
        end
    end
    d_count = counts_by_col(table, :directory)
    l_count = counts_by_col(table, :language)
    sl_count = counts_by_col(table, :sublanguage)
    sort!(table, by=row -> (d_count[row.directory], l_count[row.language], sl_count[row.sublanguage]), rev=true)
    return table
end

function counts_by_col(table, col)
    vals = unique(getproperty(row, col) for row in table)
    return Dict(val => sum(row.code for row in table if getproperty(row, col) == val) for val in vals)
end

function loc_update!(d, key, new)
    prev = get!(d, key, (; files=0, code=0, comments=0, docstrings=0, blanks=0))
    d[key] = (; files=prev.files + 1, code=prev.code + new.code, comments=prev.comments + new.comments, docstrings=0, blanks=prev.blanks + new.blanks)
end


#####
##### Counting helpers
#####

count_commits(table) = sum(row.contributions for row in table; init=0)
count_commits(pkg::Package) = count_commits(pkg.contributors)

count_contributors(table; type="User") = count(row.type == type for row in table)
count_contributors(pkg::Package; kwargs...) = count_contributors(pkg.contributors; kwargs...)


count_julia_loc(table, dir) = sum(row.code for row in table if row.directory == dir && row.language == :Julia; init=0)

count_docstrings(table, dir) = sum(row.docstrings for row in table if row.directory == dir && row.language == :Julia; init=0)

function count_docs(table, dirs=("docs", "doc"))
    rm_langs = (:TOML, :SVG, :CSS, :Javascript)
    sum(row.code + row.comments for row in table if lowercase(row.directory) in dirs && row.language ∉ rm_langs && row.sublanguage ∉ rm_langs; init=0)
end

count_readme(table) = count_docs(table, ("readme", "readme.md"))

count_julia_loc(pkg::Package, args...) = count_julia_loc(pkg.lines_of_code, args...)
count_docstrings(pkg::Package, args...) = count_docstrings(pkg.lines_of_code, args...)
count_docs(pkg::Package, args...) = count_docs(pkg.lines_of_code, args...)
count_readme(pkg::Package, args...) = count_readme(pkg.lines_of_code, args...)

#####
##### Custom Julia line counting
#####

# We can't do this at the level of SyntaxNode's because we've lost whitespace & comments already
# So we will go to GreenNode's

# Avoid piracy by defining AbstractTrees definitions on a wrapper
struct GreenNodeWrapper
    node::JuliaSyntax.GreenNode{JuliaSyntax.SyntaxHead}
    source::JuliaSyntax.SourceFile
end

function AbstractTrees.children(wrapper::GreenNodeWrapper)
    return map(n -> GreenNodeWrapper(n, wrapper.source), JuliaSyntax.children(wrapper.node))
end

function parse_green_one(file_path)
    file = read(file_path, String)
    @debug(string("Parsing ", file_path))
    parsed = try
        JuliaSyntax.parseall(JuliaSyntax.GreenNode, file; ignore_trivia=false)
    catch e
        @debug "Error during `JuliaSyntax.parse`" file_path exception = (e, catch_backtrace())
        # Return dummy result
        [JuliaSyntax.GreenNode("Error", 0, ())]
    end
    return GreenNodeWrapper(parsed, JuliaSyntax.SourceFile(file; filename=basename(file_path)))
end


function CategorizeLines.LineCategories(node::GreenNodeWrapper)
    per_line_category = LineCategories(node.source, Dict{Int,LineCategory}())
    categorize_lines!(per_line_category, node.node, node.source)
    return per_line_category
end

# This can be used to easily see the categorization, e.g.
# PackageAnalyzer.LineCategories(pathof(PackageAnalyzer))
CategorizeLines.LineCategories(path::AbstractString; kw...) = LineCategories(parse_green_one(path); kw...)


# TODO:
# Handle `@doc` calls?
# What about inline comments #= comment =#?
# Can a docstring not start at the beginning of a line?
# Can there be multiple string nodes on the same line as a docstring?

function identify_lines!(d, x)
    for node in x
        kind = node.kind
        parent_kind = node.parent_kind
        if kind == K"Comment"
            line_category = Comment
        elseif kind == K"NewlineWs"
            line_category = Blank
        elseif parent_kind == K"doc" && kind == K"string"
            line_category = Docstring
        else
            line_category = Code
        end
        upsert!(d, node.starting_line, node.ending_line, line_category)
    end
    return nothing
end

function _count_lines!(counts, node::GreenNodeWrapper)
    cats = LineCategories(node)
    for v in values(cats.dict)
        counts[v] += 1
    end
    return nothing
end

function count_julia_loc(dir)
    table = LoCTableEltype[]
    for path in readdir(dir; join=true)
        n_files = 0
        counts = Dict{LineCategory,Int}(Comment => 0,
            Blank => 0,
            Code => 0,
            Docstring => 0)
        if isfile(path)
            endswith(path, ".jl") || continue
            node = parse_green_one(path)
            _count_lines!(counts, node)
            n_files += 1
        else
            for (root, dirs, files) in walkdir(path)
                for file_name in files
                    if endswith(file_name, ".jl")
                        node = parse_green_one(joinpath(root, file_name))
                        _count_lines!(counts, node)
                        n_files += 1
                    end
                end
            end
        end
        if n_files > 0
            push!(table, (; directory=basename(path), language=:Julia,
                sublanguage=nothing, files=n_files,
                code=counts[Code],
                comments=counts[Comment],
                docstrings=counts[Docstring],
                blanks=counts[Blank]))
        end
    end
    return table
end
