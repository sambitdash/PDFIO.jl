export PDOutline,
    PDOutlineItem,
    PDOutlineIter,
    item_level,
    items_count,
    items

using LabelNumerals
using RomanNumerals
using ..Cos

####################################################################################
## Data Structures
"""
```
    PDOutlineItem
```
Representation of PDF document Outline item.

It is currently defined as `Dict{Symbol, Any}`.
Check description of function `pdDocGetOutline` for more information.

Methods which operate on this structure:
- `item_level(item::PDOutlineItem)` - return nesting level of item inside whole Outline.
"""
PDOutlineItem = Dict{Symbol, Any}

"""
```
    PDOutline
```
Representation of PDF document Outline (Table of Contents).

It is currently defined as `Vector{Union{PDOutlineItem, Vector}}`.
Check description of function `pdDocGetOutline` for more information.

Methods which operate on this structure:
- `items_count(o::PDOutline; depth::Number = Inf)` - return number of items inside Outline.
- `items(o::PDOutline; depth::Number = Inf)` - return iterator thru Outline items.
"""
PDOutline = Vector{Union{PDOutlineItem, Vector}}

####################################################################################
## Reading Outline from PDF
function get_outline_node_compact(
            cosDoc::CosDoc,
            first_ref::CosIndirectObjectRef,
            last_ref::CosIndirectObjectRef,
            curr_depth::Int,
            max_depth::Number,
            index::Vector{Int})
    arr = PDOutline()
    support_index = length(index) > 0
    curr_ref = first_ref
    while true
        obj = cosDocGetObject(cosDoc, curr_ref)
        title_ref = get(obj, cn"Title")
        title = cosDocGetObject(cosDoc, title_ref)
        if title !== CosNull
            item = PDOutlineItem()
            title isa CosIndirectObject && (title = title.obj)
            item[:Title] = convert(CDTextString, title)
            if support_index
                item[:Index] = tuple(index...)
                index[end] = index[end] + 1
            elseif curr_depth > 0
                item[:Level] = curr_depth + 1
            end
            push!(arr, item)
            ref_nest = get(obj, cn"First")
            if ref_nest !== CosNull && curr_depth < max_depth
                support_index && push!(index, 1)
                push!(arr, get_outline_node_compact(cosDoc, ref_nest, get(obj, cn"Last"), curr_depth + 1, max_depth, index))
                if support_index
                    pop!(index)
                    index[end] = index[end] + 1
                end
            end
        end
        curr_ref == last_ref && break
        curr_ref = get(obj, cn"Next")
        curr_ref === CosNull && break
    end
    return arr
end

get_outline_node_compact(
            ::CosDoc,
            ::CosNullType,
            ::CosObject,
            ::Int,
            ::Number,
            ::Vector{Int}) = nothing

## Refers to PDF 32000-1:2008 / 12.4.2
function find_label_for_page(cosDoc::CosDoc, values::Vector{Tuple{Int,CosObject}},
                             pgnum::Int, ::String)
    # @show values
    curobj = nothing
    curpg = 0
    for (pageno, obj) in values
        pageno > pgnum && break
        curobj = obj
        curpg = pageno
    end
    curobj === nothing && return nothing

    dict = cosDocGetObject(cosDoc, curobj)
    dict_s  = get(dict, cn"S")
    dict_p  = get(dict, cn"P")
    dict_st = get(dict, cn"St")
    pref  = dict_p  === CosNull ? "" : String(dict_p)
    start = dict_st === CosNull ? 1 : convert(Int, get(dict_st))
    labelpgnum = start + pgnum - curpg - 1

    dict_s == cn"D" && return LabelNumeral(Int, labelpgnum; prefix = pref)
    dict_s == cn"R" && return LabelNumeral(RomanNumeral, labelpgnum; prefix = pref)
    dict_s == cn"r" && return LabelNumeral(RomanNumeral, labelpgnum; prefix = pref, caselower=true)
    dict_s == cn"A" && return LabelNumeral(AlphaNumeral, labelpgnum; prefix = pref)
    dict_s == cn"a" && return LabelNumeral(AlphaNumeral, labelpgnum; prefix = pref, caselower=true)
    return pref
end

# Candidate for API function
function get_page_label(cosDoc::CosDoc, pgnum::Int)
    catalog = cosDocGetRoot(cosDoc)
    ref = get(catalog, cn"PageLabels")
    ref === CosNull && return nothing
    plroot = cosDocGetObject(cosDoc, ref)
    troot = Cos.createTreeNode(Int, plroot)
    return Cos.find_ntree(find_label_for_page, cosDoc, troot, pgnum, "")[2]
end

function find_named_dest_in_vector(::CosDoc, values::Vector{Tuple{String,CosObject}},
                                   dest_name::String, refdata::String)
    for (name, dest) in values
        name == dest_name && return dest
    end
    return (-1, nothing)
end

function find_named_dest(cosDoc::CosDoc, dest_name::String)
    catalog = cosDocGetRoot(cosDoc)
    ref = get(catalog, cn"Names")
    if ref !== CosNull
        obj = cosDocGetObject(cosDoc, ref)
        ref = get(obj, cn"Dests")
        if ref !== CosNull
            obj = cosDocGetObject(cosDoc, ref)
            troot = Cos.createTreeNode(String, obj)
            found = Cos.find_ntree(find_named_dest_in_vector, cosDoc, troot, dest_name, "")
            return found[2]
        end
    end
    return nothing
end

# Refers to PDF 32000-1:2008 / 12.3.3
function get_outline_node_full(
            cosDoc::CosDoc,
            first_ref::CosIndirectObjectRef,
            last_ref::CosIndirectObjectRef,
            curr_depth::Int,
            max_depth::Number,
            index::Vector{Int},
            pgmap::Dict{CosIndirectObjectRef, Int})
    catalog = cosDocGetRoot(cosDoc)
    ref = get(catalog, cn"PageLabels")
    plroot = nothing
    if ref !== CosNull
        obj = cosDocGetObject(cosDoc, ref)
        plroot = Cos.createTreeNode(Int, obj)
    end
    ref = get(catalog, cn"Names")
    destroot = nothing
    if ref !== CosNull
        obj = cosDocGetObject(cosDoc, ref)
        ref = get(obj, cn"Dests")
        if ref !== CosNull
            obj = cosDocGetObject(cosDoc, ref)
            destroot = Cos.createTreeNode(String, obj)
        end
    end

    curr_ref = first_ref
    arr = PDOutline()
    support_index = length(index) > 0
    while true
        obj = cosDocGetObject(cosDoc, curr_ref)
        title_ref = get(obj, cn"Title")
        title = cosDocGetObject(cosDoc, title_ref)
        if title !== CosNull
            item = PDOutlineItem()
            title isa CosIndirectObject && (title = title.obj)
            item[:Title] = convert(CDTextString, title)
            if support_index
                item[:Index] = tuple(index...)
                index[end] = index[end] + 1
            elseif curr_depth > 0
                item[:Level] = curr_depth + 1
            end
            ref = get(obj, cn"Count")
            if ref != CosNull
                item[:Expanded] = convert(Int, ref) > 0
            end
            ref = get(obj, cn"F")
            if ref != CosNull
                item[:Style] = convert(Int, ref)
            end
            ref = get(obj, cn"Dest")
            if ref != CosNull && ref isa CosArray
                pg = get(ref)[1]
                item[:PageRef] = pg
                try
                    item[:PageNo] = pgmap[pg]
                catch KeyError
                    throw(ErrorException(E_INVALID_OBJECT))
                end
            end
            ref = get(obj, cn"A")
            if ref != CosNull
                action = get(cosDocGetObject(cosDoc, ref))
                if action isa Dict && action[cn"S"] == cn"GoTo"
                    # Refers to PDF 32000-1:2008 / 12.6.4.2
                    if action[cn"D"] isa CosIndirectObjectRef
                        item[:PageRef] = action[cn"D"]
                        try
                            item[:PageNo] = pgmap[action[cn"D"]]
                        catch KeyError
                            throw(ErrorException(E_INVALID_OBJECT))
                        end
                    elseif action[cn"D"] isa Cos.CosLiteralString  # PS: Shouldn't this type be exported?
                        dest_name = String(action[cn"D"])
                        if destroot !== nothing
                            dest_ref = Cos.find_ntree(find_named_dest_in_vector, cosDoc, destroot, dest_name, "")[2]
                            if dest_ref !== nothing
                                dest_obj = get(cosDocGetObject(cosDoc, dest_ref))
                                if dest_obj isa Dict
                                    dest_obj = dest_obj[cn"D"]
                                end
                                if dest_obj != CosNull && dest_obj isa CosArray
                                    pg = get(dest_obj)[1]
                                    item[:PageRef] = pg
                                    try
                                        item[:PageNo] = pgmap[pg]
                                    catch KeyError
                                        throw(ErrorException(E_INVALID_OBJECT))
                                    end
                                end
                            end
                        end
                    end
                end
            end
            ref = get(obj, cn"SE")
            if ref != CosNull
                # Please open <Issue> on github and provide document that uses this entry
                throw(ErrorException(E_NOT_IMPLEMENTED))
            end

            if plroot !== nothing && haskey(item, :PageNo)
                label = Cos.find_ntree(find_label_for_page, cosDoc, plroot, item[:PageNo], "")[2]
                label !== nothing && (item[:PageLabel] = label)
            end

            push!(arr, item)
            ref_nest = get(obj, cn"First")
            if ref_nest !== CosNull && curr_depth < max_depth
                support_index && push!(index, 1)
                push!(arr, get_outline_node_full(cosDoc, ref_nest, get(obj, cn"Last"), curr_depth + 1, max_depth, index, pgmap))
                if support_index
                    pop!(index)
                    index[end] = index[end] + 1
                end
            end
        end
        curr_ref == last_ref && break
        curr_ref = get(obj, cn"Next")
        curr_ref === CosNull && break
    end
    return arr
end

get_outline_node_full(
            ::CosDoc,
            ::CosNullType,
            ::CosObject,
            ::Int,
            ::Number,
            ::Vector{Int},
            ::Dict) = nothing

"""
```
    item_level(item::PDOutlineItem) -> Int
```
Return nesting level of item inside whole Outline.
"""
function item_level(item::PDOutlineItem)
    haskey(item, :Level) && return item[:Level]
    haskey(item, :Index) && return length(item[:Index])
    return 1
end

####################################################################################
## Support for iteraring thru Outline
struct PDOutlineIter
    outline::PDOutline
    max_depth::Number
end

"""
```
    items_count(o::PDOutline; depth::Number = Inf) -> Int
    items_count(item::PDOutlineItem; depth::Number = Inf) -> Int
```
Return number of items inside Outline.
Only the first method is practical, second one always return 1.
Use `depth` parameter if you want to count to certain nesting level (0 means root level).
"""
items_count(item::PDOutlineItem; depth::Number = Inf) = 1
function items_count(o::PDOutline; depth::Number = Inf)
    depth < 0 && return 0
    len = 0
    for item in o
        len = len + items_count(item; depth = depth - 1)
    end
    return len
end

"""
```
    items(o::PDOutline; depth::Number = Inf) -> PDOutlineIter
```
Return iterator that can be used to iterate thru Outline items.
This method can be also used to flatten Outline structure: `outline |> items |> colect`.
Use `depth` parameter if you want to iterate to certain nesting level (0 means root level).
"""
items(o::PDOutline; depth::Number = Inf) = PDOutlineIter(o, depth)

Base.length(oi::PDOutlineIter) = items_count(oi.outline, depth = oi.max_depth)
Base.eltype(::PDOutlineIter) = PDOutlineItem

# state: (curr_vec::Vector, curr_vec_it::Any, parent_state::NTuple)
function Base.iterate(oi::PDOutlineIter)
    it = iterate(oi.outline)
    return it === nothing ? nothing : (it[1], (oi.outline, it[2], nothing))
end
function Base.iterate(oi::PDOutlineIter, state)
    it = iterate(state[1], state[2]) #Vector iterator (not recurance)
    if it === nothing
        state[3] === nothing && return nothing
        return iterate(oi, state[3])
    end
    if it[1] isa PDOutlineItem
        return (it[1], (state[1], it[2], state[3]))
    end
    itn = iterate(it[1]) #Vector iterator (not recurance)
    if itn === nothing # empty vector - may happen in ill-formed PDFs
        return iterate(oi, (state[1], it[2], state[3])) # try next position from current vector
    end
    @assert itn[1] isa PDOutlineItem # first item in group should be an outline item
    if item_level(itn[1]) - 1 > oi.max_depth
        return iterate(oi, (state[1], it[2], state[3])) # try next position from current vector
    end
    return (itn[1], (it[1], itn[2], (state[1], it[2], state[3]))) # it[1] must be a vector, nest into
end

####################################################################################
## Support for printing outline in more readable form
function Base.show(io::IO, item::PDOutlineItem; indent::Bool = false)
    if indent
        if haskey(item, :Index)
            map(i -> print(io, "[" * string(i) * "]"), item[:Index])
            print(io, ": ")
        elseif haskey(item, :Level)
            print(io, "  " ^ (item[:Level] - 1))
        end
    end
    :Title in keys(item) && print(io, item[:Title])
    for (k, v) in item
        k == :Title && continue
        indent && k ∈ (:Level, :Index) && continue
        print(io, " | ")
        print(io, k)
        print(io, "=>")
        print(io, v)
    end
end
function Base.show(io::IO, ::MIME"text/plain", item::PDOutlineItem; indent::Bool = false)
    summary(io, item)
    println(io, ":")
    show(io, item; indent = indent)
end

function Base.show(io::IO, o::PDOutline; depth::Number = Inf)
    for item in items(o, depth = depth)
        show(io, item, indent = true)
        print(io, '\n')
    end
end
function Base.show(io::IO, ::MIME"text/plain", o::PDOutline; depth::Number = Inf)
    summary(io, o)
    println(io, ":")
    show(io, o; depth = depth)
end
Base.show(o::PDOutline; depth::Number = Inf) = show(stdout::IO, o; depth = depth)
