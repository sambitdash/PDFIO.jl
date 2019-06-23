export PDOutline,
    PDDestination,
    PDOutlineItem,
    pdOutlineItemGetAttr

using ..Cos
using AbstractTrees
import AbstractTrees: children, printnode

abstract type _ParentNode  end

"""
```
    PDDestination
```

Used for variety of purposes to locate a rectangular region in a PDF document.
Particularly, used in outlines, actions etc.

The structure can denote a location outside of a document as well like in remote
GoTo(GoToR) actions. In such cases, it's best be used with filename additionally.
Moreover, page references have no meaning in remote file references. Hence, the
`pageno` attribute has been set to `Int` unlike the PDF Spec 32000-2008 12.3.2.2.

    - `pageno::Int` - Page number location
    - `layout::CosName` - Various view layouts are possible. Please review the
PDF spec for details. 
    - `values::Vector{Float32}` - [left, bottom, right, top] sequence array. Not
    all values are used. The usage depends on the `layout` parameter.
    - `zoom::Float32` - Zoom value for the view. Can be `zero` depending on
    - `layout` where it's intrinsic; hence, redundant.
"""
struct PDDestination
    pageno::Int
    layout::CosName
    values::Vector{Float32}
    zoom::Float32
end

ifnull(x, y) = x !== CosNull ? x : y

function PDDestination(doc::PDDoc, arr::CosArray)
    v = get(arr)
    page = pd_doc_get_pagenum(doc, v[1])
    values = [0f0, 0f0, 0f0, 0f0]
    zoom = 0f0
    if     v[2] === cn"XYZ"
        values[1] = ifnull(v[3], 0f0)
        values[4] = ifnull(v[4], 0f0)
        zoom      = ifnull(v[5], 0f0)
    elseif v[2] === cn"Fit"
    elseif v[2] === cn"FitH"
        values[4] = ifnull(v[3], 0f0)
    elseif v[2] === cn"FitV"
        values[1] = ifnull(v[4], 0f0)
    elseif v[2] === cn"FitR"
        values[1] = ifnull(v[3], 0f0)
        values[2] = ifnull(v[4], 0f0)
        values[3] = ifnull(v[5], 0f0)
        values[4] = ifnull(v[6], 0f0)
    elseif v[2] === cn"FitB"
    elseif v[2] === cn"FitBH"
        values[4] = ifnull(v[3], 0f0)
    elseif v[2] === cn"FitBV"
        values[1] = ifnull(v[3], 0f0)
    end
    return PDDestination(page, v[2], values, zoom)
end

"""
```
    PDOutlineItem
```
Representation of PDF document Outline item.

"""
mutable struct PDOutlineItem <: _ParentNode
    doc::PDDoc
    cosdict::ID{CosDict}
    parent::_ParentNode
    prev::Union{PDOutlineItem, Nothing}
    next::Union{PDOutlineItem, Nothing}
    first::Union{PDOutlineItem, Nothing}
    last::Union{PDOutlineItem, Nothing}
    PDOutlineItem(doc::PDDoc, cosdict::ID{CosDict}, parent::_ParentNode) = 
        new(doc, cosdict, parent, nothing, nothing, nothing, nothing)
end

show(io::IO, x::PDOutlineItem) = showref(io, x.cosdict)

populate_outline_items!(parent::_ParentNode, ::CosNullType, ::CosNullType) =
    (parent.first = parent.last = nothing)

@inline function populate_outline_items!(parent::_ParentNode,
                                         first_obj::ID{CosDict},
                                         last_obj::ID{CosDict})
    cosdoc = parent.doc.cosDoc
    curr_obj = first_obj
    prev_obj = cosDocGetObject(cosdoc, curr_obj, cn"Prev")
    @assert prev_obj === CosNull
        "Outline first item with invalid /Prev attribute"
    first = curr = PDOutlineItem(parent.doc, curr_obj, parent)
    curr.prev = nothing
    while true
        cfirst_obj = cosDocGetObject(cosdoc, curr_obj, cn"First")
        clast_obj  = cosDocGetObject(cosdoc, curr_obj, cn"Last")
        populate_outline_items!(curr, cfirst_obj, clast_obj)

        next_obj = cosDocGetObject(cosdoc, curr_obj, cn"Next")
        if next_obj === CosNull
            @assert curr_obj === last_obj "Invalid /Last attribute in outlines"
            break
        end
        prev_obj = cosDocGetObject(cosdoc, next_obj, cn"Prev")
        @assert prev_obj === curr_obj
            "Outline item with invalid /Prev attribute"
        curr.next = PDOutlineItem(parent.doc, next_obj, parent)
        prev = curr
        curr_obj,  curr = next_obj, curr.next
        curr.prev       = prev
    end
    parent.first, parent.last = first, curr
    return nothing
end

"""
```
    pdOutlineItemGetAttr(item::PDOutlineItem) -> Dict{Symbol, Any}
```

Attributes stored with an `PDOutlineItem` object. The traversal parameters like
`Prev`, `Next`, `First`, `Last` and `Parent` are stored with the structure.

The following keys are stored in the dictionary object returned:

- `:Title` - The title assigned to the item (shows up in the table of content)
- `:Count` - A representation of no of items open under the outline item. Please
refer to the PDF Spec 32000-2008 section 12.3.2.2 for details. Mostly, used for
rendering on a user interface.
- `:Destination` - `(filepath, PDDestination)` value. Filepath is an empty string
if the destination refers to a location in the same PDF file. This parameter is
a combination of `/Dest` and `/A` attribute in the PDF specification. The action
element is analyzed and data is extracted and stored with the `PDDestination` as
the final refered location.
- `:C` - The color of the outline in the `DeviceRGB` space.
- `:F` - Flags for title text rendering `italic=1`, `bold=2`

# Example

```
    julia> pdOutlineItemGetAttr(outlineitem)
Dict{Symbol,Any} with 5 entries:
  :F           => 0x00
  :Title       => "Table of Contents"
  :Count       => 0
  :Destination => ("", PDDestination(2, /XYZ, Float32[0.0, 0.0, 0.0, 756.0], 0.0))
  :C           => Float32[0.0, 0.0, 0.0]
```
"""
function pdOutlineItemGetAttr(item::PDOutlineItem)
    doc, cosdoc, dict = item.doc, item.doc.cosDoc, item.cosdict
    retval = Dict{Symbol, Any}()
    title_obj = cosDocGetObject(cosdoc, dict, cn"Title")
    @assert title_obj !== CosNull "Invalid outline item without title"
    retval[:Title] = CDTextString(title_obj)
    count_obj = cosDocGetObject(cosdoc, dict, cn"Count")
    retval[:Count] = count_obj === CosNull ? 0 : get(count_obj)

    dest_obj = cosDocGetObject(cosdoc, dict, cn"Dest")

    dest_obj === CosNull &&
        (dest_obj = cosDocGetObject(cosdoc, dict, cn"A"))

    dest_obj !== CosNull &&
        (retval[:Destination] = get_outline_destination(doc, dest_obj))
    
    c_obj    = cosDocGetObject(cosdoc, dict, cn"C")
    retval[:C] = c_obj === CosNull ? [0f0, 0f0, 0f0] : get(c_obj, true)

    f_obj    = cosDocGetObject(cosdoc, dict, cn"F")
    retval[:F] = f_obj === CosNull ? 0x00 : UInt8(get(f_obj))

    return retval
end

get_outline_destination(doc::PDDoc, dest_obj::CosIndirectObject{CosArray}) =
    "", PDDestination(doc, dest_obj.obj)
    
get_outline_destination(doc::PDDoc, dest_obj::CosArray) =
    "", PDDestination(doc, dest_obj)

function get_outline_destination(doc::PDDoc,
                                 dest_obj::Union{IDD{CosLiteralString},
                                                 IDD{CosXString}})
    catalog = pdDocGetCatalog(doc)
    cosdoc = doc.cosDoc
    tname = CDTextString(dest_obj)
    named_dest = cosDocGetObject(cosdoc, catalog, cn"Dests")
    if named_dest !== CosNull
        dest_obj = cosDocGetObject(cosdoc, named_dest, CosName(tname))
        dest_obj !== CosNull && return "", PDDestination(doc, dest_obj)
    end
    
    name_dict_obj = cosDocGetObject(cosdoc, catalog, cn"Names")
    @assert name_dict_obj !== CosNull "Document with no /Names dictionary"
    dest_nametree_obj = cosDocGetObject(cosdoc, name_dict_obj, cn"Dests")
    @assert dest_nametree_obj !== CosNull
        "Document with no /Dests in /Names dictionary"
    troot = createTreeNode(String, dest_nametree_obj)
    found = find_ntree(cosdoc, troot, tname, "") do doc, vs, key, refdata
        for (name, dest) in vs
            name == tname && return dest
        end
        return -1, nothing
    end
    return get_outline_destination(doc, cosDocGetObject(cosdoc, found[2]))
end

function get_outline_destination(doc::PDDoc, action::IDD{CosDict})
    cosdoc = doc.cosDoc
    s = cosDocGetObject(cosdoc, action, cn"S")
    d = cosDocGetObject(cosdoc, action, cn"D")
    f = cosDocGetObject(cosdoc, action, cn"F")

    @assert (f !== CosNull && s === cn"GoToR") ||
            (f === CosNull && (s === cn"GoTo" || s === CosNull))
        "Invalid remote goto action with no filename specifier"
    filepath = f === CosNull ? "" : CDTextString(f)
    dest = get_outline_destination(doc, d)
    return filepath, dest[2]
end

"""
```
    PDOutline
```
Representation of PDF document Outline (Table of Contents).

Use the methods from `AbstractTrees` package to traverse the elements.

"""
mutable struct PDOutline <: _ParentNode
    doc::PDDoc
    cosdict::ID{CosDict}
    first::Union{Nothing, PDOutlineItem}
    last::Union{Nothing, PDOutlineItem}
    count::Int    
    PDOutline(doc::PDDoc, cosdict::ID{CosDict}, count::Int) =
        new(doc, cosdict, nothing, nothing, count)
end

show(io::IO, x::PDOutline) = showref(io, x.cosdict)

@inline function PDOutline(doc::PDDoc, tocobj::ID{CosDict})
    cosDoc = doc.cosDoc
    outline = PDOutline(doc, tocobj, 0)
    first_obj = cosDocGetObject(cosDoc, tocobj, cn"First")
    last_obj  = cosDocGetObject(cosDoc, tocobj, cn"Last")
    populate_outline_items!(outline, first_obj, last_obj)
    return outline
end

# These are interfaces for tree traversal provided wuth AbstractTrees
# interfaces. One can use these methods to traverse through the
# PDOutline and PDOutlineItem objects.

children(tn::_ParentNode) = tn.first === nothing ? () : collect(tn.first)
getindex(tn::_ParentNode, i::Int) = children(tn)[i]

printnode(io::IO, it::PDOutline) = print(io, "Contents")

function printnode(io::IO, it::PDOutlineItem)
    cosdoc, cosdict = it.doc.cosDoc, it.cosdict
    title_obj = cosDocGetObject(cosdoc, cosdict, cn"Title")
    print(io, CDTextString(title_obj))
end
    
Base.iterate(tn::PDOutlineItem) = tn, tn.next
Base.iterate(tn::PDOutlineItem, ::Nothing) = nothing
Base.iterate(tn::PDOutlineItem, state::PDOutlineItem) = state, state.next

Base.IteratorSize(tn::PDOutlineItem) = Base.SizeUnknown()
Base.eltype(it::PDOutlineItem) = PDOutlineItem
Base.similar(it::PDOutlineItem) = Vector{eltype(it)}()

