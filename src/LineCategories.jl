# Here, we assign a category to every line of a file, with help from JuliaSyntax
# Module to make it easier w/r/t/ import clashes
module CategorizeLines
export LineCategories, LineCategory, Blank, Code, Docstring, Comment, categorize_lines!

using JuliaSyntax: GreenNode, is_trivia, haschildren, is_error, children, span, SourceFile, source_location, Kind, kind, @K_str

# Every line will have a single category. This way the total number across all categories
# equals the total number of lines. This is useful for debugging and is reassuring to users.
# However, a line may have multiple things on it, including comments, docstrings, code, etc.
# We will choose the single category by a simple precedence rule, given by the following ordering.

# Some constructs should apply to all lines between them counting, while other's shouldn't. For example, `module ... end` should have `module` and `end` counting
# as code, but not necessarily all the stuff in between. Whereas for docstrings,
# if we have a big docstring block, we do want to count all the lines in between as docstring.
# So in the implementation, we treat `Code` as only applying to the first and last line,
# while the rest apply to all intermediate lines.

# For the ordering itself, we put `Blank` lowest, since if there's anything else on the line, we want to count it as that.
# We put `Code` next, since it is the fallback, and we don't want it to override when we have more specific information.
# Then comment, then docstring, so comments inside of docstrings count as docstrings.
"""
    LineCategory

An `enum` corresponding to the possible categorization of a line of Julia source code.
Currently:
* `Blank`
* `Code`
* `Comment`
* `Docstring`
"""
@enum LineCategory Blank Code Comment Docstring

# We will store the categories assigned to each line in a file with the following structure.
# This keeps the `SourceFile` to facillitate printing.
"""
    LineCategories(path)

Categorize each line in a file as a [`PackageAnalyzer.LineCategory`](@ref).
Every line is assigned a single category.
"""
struct LineCategories
    source::SourceFile
    dict::Dict{Int,LineCategory}
end

# Update the `category` for lines `start_line:ending_line`
function update!(lc::LineCategories, starting_line::Int, ending_line::Int, category::LineCategory; inclusive)
    if inclusive
        range = starting_line:ending_line
    else
        range = (starting_line, ending_line)
    end

    for line in range
        # Would be nice to have a `Dict` API to do this with a single lookup
        current = get(lc.dict, line, LineCategory(0))
        lc.dict[line] = max(current, category)
    end
end

# Print back out the source, but with line categories
function Base.show(io::IO, ::MIME"text/plain", per_line_category::LineCategories)
    source = per_line_category.source
    f = true
    for idx in sort!(collect(keys(per_line_category.dict)))
        f || println(io)
        f = false
        line_start = source.line_starts[idx]
        # `prevind` since this is the start of the next line, not the end of the previous one
        line_end = min(prevind(source.code, source.line_starts[idx+1]), lastindex(source.code))

        # One more prevind to chop the last line ending
        line = SubString(source.code, line_start:prevind(source.code, line_end))
        print(io, rpad(idx, 5), "| ", rpad(per_line_category.dict[idx], 9), " | ", line)
    end
    return nothing
end

# Based on the recursive printing code for GreenNode's
# Here, instead of printing, we update our line number information.
function categorize_lines!(d::LineCategories, node, source, nesting=0, pos=1, parent_kind=nothing)
    starting_line, _ = source_location(source, pos)
    k = kind(node)

    # Recurse over children
    is_leaf = !haschildren(node)
    if !is_leaf
        new_nesting = nesting + 1
        p = pos
        for x in children(node)
            categorize_lines!(d, x, source, new_nesting, p, k)
            p += x.span
        end
        ending_line, _ = source_location(source, p)
    else
        ending_line = starting_line
    end

    # Update with the information we have from this level
    inclusive = true # all inclusive except `Code`
    if k == K"Comment"
        line_category = Comment
    elseif k == K"NewlineWs"
        line_category = Blank
    elseif parent_kind == K"doc" && k == K"string"
        line_category = Docstring
    else
        line_category = Code
        inclusive = false
    end
    update!(d, starting_line, ending_line, line_category; inclusive)

    return nothing
end

end
