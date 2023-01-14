using JuliaSyntax: @K_str, kind

export analyze_syntax

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

function count_interesting_things(tree::SyntaxNodeWrapper)
    counts = Dict{String, Int}()
    items = PostOrderDFS(tree)
    foreach(items) do wrapper
        k = kind(wrapper.node.raw)
        
        if k in [K"function", K"struct", K"call"]
            key = string(k)
            counts[key] = get(counts, key, 0) + 1
        elseif k in [K"export", K"using", K"import"]
            # println(k, ": ", JuliaSyntax.children(wrapper.node))
            key = string(k, "s")
            counts[key] = get(counts, key, 0) + length(JuliaSyntax.children(wrapper.node))

        end
    end
    return counts
end


# Entrypoint
function analyze_syntax(arg)
    counts = Dict{String, Int}()
    file_tree_pairs = parse_syntax_recursive(arg)
    # Do we want to track of which file has which things? Probably not that useful...
    for (file, tree) in file_tree_pairs
        file_counts = count_interesting_things(tree)
        mergewith!(+, counts, file_counts)
    end
    return counts
end
