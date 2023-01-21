export analyze_syntax

#####
##### SyntaxTrees
#####

# Avoid piracy by defining AbstractTrees definitions on a wrapper
struct SyntaxNodeWrapper
    node::JuliaSyntax.SyntaxNode
end

function AbstractTrees.children(wrapper::SyntaxNodeWrapper)
    return map(SyntaxNodeWrapper, JuliaSyntax.children(wrapper.node))
end

#####
##### Parsing files, traversing literal include statements
#####

function parse_syntax_one(file_path)
    file = read(file_path, String)
    parsed = JuliaSyntax.parse(JuliaSyntax.SyntaxNode, file)
    return SyntaxNodeWrapper(parsed[1])
end


function find_literal_includes(tree::SyntaxNodeWrapper)
    items = PostOrderDFS(tree)

    # Filter to includes
    itr = Iterators.filter(items) do wrapper
        # A literal include has kind `K"call"`, whose first children's value is the symbol `:include`,
        # and whose second child is the thing being included, which we require to be a string literal
        k = kind(wrapper.node.raw)
        k == K"call" || return false
        kids = JuliaSyntax.children(wrapper.node)
        isempty(kids) && return false
        if kids[1].val == Symbol(:include) && kind(kids[2].raw) == K"string"
            return true
        else
            return false
        end
        return true
    end

    # Grab the filenames
    return map(itr) do wrapper
        kids = JuliaSyntax.children(wrapper.node)
        return only(kids[2].val).val
    end
end

function parse_syntax_recursive(file_path)
    trees = Pair{String, SyntaxNodeWrapper}[]
    tree = parse_syntax_one(file_path)
    push!(trees, basename(file_path) => tree)
    other_files = find_literal_includes(tree)
    for file in other_files
        full_path = joinpath(dirname(file_path), file)
        more_trees = parse_syntax_recursive(full_path)
        append!(trees, more_trees)
    end
    return trees
end

function parse_syntax_recursive(pkg::Module)
    file_path = pathof(pkg)
    return parse_syntax_recursive(file_path)
end

#####
##### Do stuff with the parsed files
#####

using JuliaSyntax
using JuliaSyntax: head
function count_interesting_things(tree::SyntaxNodeWrapper)
    counts = Dict{String, Int}()

    # In case one does `using X: a` then `using X: b`, we want to count `X` only once,
    # so we keep track of the ones we've seen so far.
    # TODO: check all forms of `using` syntax and import as, etc.
    usings = Set{String}()
    imports = Set{String}()
    items = PostOrderDFS(tree)
    foreach(items) do wrapper
        k = kind(wrapper.node.raw)
        if k == K"="
            # 1-line function definitions like f() = abc...
            # Show up as an `=` with the first argument being a call
            # and the second argument being the function body.
            # We handle those here.
            # We do not handle anonymous functions like `f = () -> 1`
            kids = JuliaSyntax.children(wrapper.node)
            length(kids) == 2 || return
            kind(kids[1].raw) == K"call" || return
            key = "method"
            counts[key] = get(counts, key, 0) + 1
        elseif k == K"function"
            # This is a function like function f() 1+1 end
            key = "method"
            counts[key] = get(counts, key, 0) + 1
        elseif k == K"struct"
            # These we increment once
            key = string(k)
            counts[key] = get(counts, key, 0) + 1
        elseif k == K"using"
            # Hm... not quite right.
            union!(usings, map(x -> string(first(x.val)), JuliaSyntax.children(wrapper.node)))
        elseif k == K"import"
            union!(imports, map(x -> string(x.val), JuliaSyntax.children(wrapper.node)))
        elseif k  == K"export"
            # These we count by the number of their children, since that's the number of exports/packages
            # being handled by that invocation of the keyword
            key = string(k)
            counts[key] = get(counts, key, 0) + length(JuliaSyntax.children(wrapper.node))
        end
    end

    counts["using"] = length(usings)
    counts["import"] = length(imports)

    return counts
end

function print_syntax_counts_summary(io::IO, counts, indent=0)
    total_count = item -> sum(row.count for row in counts if row.item == item; init=0)
    n_struct = total_count("struct")
    n_method = total_count("method")
    n_export = total_count("export")
    n_using = total_count("using")
    n_import = total_count("import")
    n = maximum(ndigits(x) for x in (n_struct, n_method, n_export, n_using, n_import))
    _print = (num, name) -> println(io, " "^indent, "* ", rpad(num, n), " ", name)
    _print(n_export, "exports")
    _print(n_using, "packages or modules loaded by `using`")
    _print(n_import, "packages or modules loaded by `import`")
    _print(n_struct, "struct definitions")
    _print(n_method, "method definitions")
    return nothing
end

#####
##### Entrypoint
#####

function analyze_syntax(arg)
    table = ParsedCountsEltype[]
    file_tree_pairs = parse_syntax_recursive(arg)
    for (file_name, tree) in file_tree_pairs
        file_counts = count_interesting_things(tree)
        for (item, count) in file_counts
            push!(table, (; file_name, item, count))
        end
    end
    return table
end

#####
##### Count lines
#####



# We can't do this at the level of SyntaxNode's because we've lost whitespace & comments already

# function count_lines(tree)
#     items = PostOrderDFS(tree)
#     d = Dict{Int, Vector{Any}}()
#     for it in items
#         node = it.node
#         line, col = JuliaSyntax.source_location(node.source, node.position)
#         v = get!(Vector{Any}, d, line)
#         push!(v, kind(raw))
#     end

#     for k in sort!(collect(keys(d)))
#         println(k, "\t|\t", d[k])
#     end
#     return d
# end

# So we will go to GreenNode's

# Avoid piracy by defining AbstractTrees definitions on a wrapper
struct GreenNodeWrapper2
    node::JuliaSyntax.GreenNode
    source::JuliaSyntax.SourceFile
end

function AbstractTrees.children(wrapper::GreenNodeWrapper2)
    return map(n -> GreenNodeWrapper2(n, wrapper.source), JuliaSyntax.children(wrapper.node))
end

function parse_green_one(file_path)
    file = read(file_path, String)
    parsed = JuliaSyntax.parse(JuliaSyntax.GreenNode, file; ignore_trivia=false)
    return GreenNodeWrapper2(parsed[1], JuliaSyntax.SourceFile(file; filename=basename(file_path)))
end

# Module to make it easier w/r/t/ import clashes

module CategorizeLines
using JuliaSyntax: GreenNode, is_trivia, haschildren, is_error, children, span, SourceFile, source_location
# Pretty printing
function _categorize_lines!(d, node, source, nesting, pos)
    starting_line_number, col = source_location(source, pos)
    v = get!(Vector{Any}, d, starting_line_number)

    is_leaf = !haschildren(node)
    if !is_leaf
        new_nesting = nesting + 1
        p = pos
        for x in children(node)
            _categorize_lines!(d, x, source, new_nesting, p)
            p += x.span
        end
        ending_line_number, _ = source_location(source, p)
    else
        ending_line_number = starting_line_number
    end
    push!(v, (; starting_line_number, ending_line_number, is_error=is_error(node), is_leaf, is_trivia=is_trivia(node), nesting, summary=summary(node)))
    return nothing
end


function categorize_lines!(d, node::GreenNode, source::SourceFile)
    _categorize_lines!(d, node, source, 0, 1)
end

end

using .CategorizeLines

function identify_lines!(d2, v)
    if v[1].summary == "Comment"
        d2[v[1].starting_line_number] = "Comment"
    elseif v[1].summary == "NewlineWs"
        d2[v[1].starting_line_number] = "Blank"
    elseif v[1].summary == "core_@doc"
            idx = findfirst(x -> x.summary == "string", v)
            for line in v[1].starting_line_number:v[idx].ending_line_number
                d2[line] = "Docstring"
            end
    else
        # Don't overwrite e.g. docstrings
        if !haskey(d2, v[1].starting_line_number)
            str = join((x.summary for x in v), ", ")
            d2[v[1].starting_line_number] = "Code ($str)"
        end
    end
end

function categorize_lines(node::GreenNodeWrapper2; show=false)
    d = Dict{Int, Vector{Any}}()
    CategorizeLines.categorize_lines!(d, node.node, node.source)
    d2 = Dict{Int, String}()

    for k in sort!(collect(keys(d)))
        identify_lines!(d2, d[k])
    end

    if show
        for k in sort!(collect(keys(d2)))
            println(k, "\t|\t", d2[k])
        end
    end
    return d2
end

function count_lines(dir)
    vals = []
    for (root, dirs, files) in walkdir(dir)
        for file_name in files
            if endswith(file_name, ".jl")
                node = parse_green_one(joinpath(root, file_name))
                append!(vals, count_lines(node; file_name))
            end
        end
    end
    return identity.(vals)
end

function count_lines(node::GreenNodeWrapper2; file_name="")
    cats = categorize_lines(node; show=false)
    counts = Dict{String, Int}("Comment" => 0, "Blank" => 0, "Code" => 0, "Docstring" => 0)

    for v in values(cats)
        if startswith(v, "Code")
            counts["Code"] += 1
        else
            counts[v] += 1
        end
    end

    return [ (; file_name, type, count ) for (type, count) in counts]
end
# TODO:
# Handle `@doc` calls?
# What about inline comments #= comment =#?
# Can a docstring not start at the beginning of a line?
# Can there be multiple string nodes on the same line as a docstring?
