export PDOutline,
    PDOutlineItem

using ..Cos
using AbstractTrees
import AbstractTrees: children, printnode

abstract type _ParentNode  end

####################################################################################
## Data Structures
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

populate_outline_items(parent::_ParentNode,
                       ::CosNullType, ::CosNullType) = (nothing, nothing)

@inline function populate_outline_items(parent::_ParentNode,
                                        first_obj::ID{CosDict},
                                        last_obj::ID{CosDict})
    cosdoc = parent.doc.cosDoc
    curr_obj = first_obj
    prev_obj = cosDocGetObject(cosdoc, curr_obj, cn"Prev")
    @assert prev_obj === CosNull
        "Outline first item with invalid /Prev attribute"
    last = first = curr = PDOutlineItem(parent.doc, curr_obj, parent)
    curr.prev = nothing
    while curr_obj !== last_obj
        next_obj = cosDocGetObject(cosdoc, curr_obj, cn"Next")
        @assert next_obj !== CosNull
            "Outline item with invalid /Next attribute"
        prev_obj = cosDocGetObject(cosdoc, next_obj, cn"Prev")
        @assert prev_obj === curr_obj
            "Outline item with invalid /Prev attribute"
        curr.next = PDOutlineItem(parent.doc, next_obj, parent)

        cfirst_obj = cosDocGetObject(cosdoc, curr_obj, cn"First")
        clast_obj  = cosDocGetObject(cosdoc, curr_obj, cn"Last")
        curr.first, curr.last =
            populate_outline_items(curr, cfirst_obj, clast_obj)
        
        prev = curr
        curr_obj,  curr = next_obj, curr.next
        curr.prev       = prev
    end
    lnext = cosDocGetObject(cosdoc, curr_obj, cn"Next")
    @assert lnext === CosNull
        "Outline last item with invalid /Next attribute"
    if last_obj !== first_obj
        last = PDOutlineItem(parent.doc, curr_obj, parent)
        last.prev = curr
    end
    last.next = nothing
    lfirst_obj = cosDocGetObject(cosdoc, curr_obj, cn"First")
    llast_obj  = cosDocGetObject(cosdoc, curr_obj, cn"Last")
    last.first, last.last =
        populate_outline_items(last, lfirst_obj, llast_obj)

    return first, last
end

"""
```
    PDOutline
```
Representation of PDF document Outline (Table of Contents).

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
    outline.first, outline.last =
        populate_outline_items(outline, first_obj, last_obj)
    return outline
end

# These are interfaces for tree traversal provided wuth AbstractTrees
# interfaces. One can use these methods to traverse through the
# PDOutline and PDOutlineItem objects.

children(tn::_ParentNode) = tn.first === nothing ? () : collect(tn.first)

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
