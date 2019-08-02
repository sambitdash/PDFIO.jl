export
    PDPageObject,
    PDPageElement,
    PDPageObjectGroup,
    PDPageTextObject,
    PDPageTextRun,
    PDPageMarkedContent,
    PDPageInlineImage,
    PDPage_BeginGroup,
    PDPage_EndGroup,
    GState

import Base: get, show, getindex, setindex!, delete!, >
import ..Common: CDRect
using ..Cos: CosComment

using LinearAlgebra


abstract type PDPage end
abstract type PDXObject end

"""
```
    PDPageObject
```

The content streams associated with PDF pages contain the objects that can be rendered.
These objects are represented by `PDPageObject`. These objects can contain
a postfix notation based operator prefixed by its operands like:
```
(Draw this text) Tj
```
As can be seen above, the string object is a [`CosString`](@ref) which is a parameter to the
operand `Tj` or draw text. These class of objects are represented by
[`PDPageElement`](@ref).

However, there are certain objects which only provide grouping information or begin and end
markers for grouping information. For example, a text object:
```
BT
    /F1 11 Tf  %selectfont
    (Draw this text) Tj
ET
```
These kind of objects are represented by [`PDPageObjectGroup`](@ref). In this case, the
[`PDPageObjectGroup`](@ref) contains four [`PDPageElement`](@ref). Namely, represented as operators `BT`,
`Tf`, `Tj`, `ET`.

`PDPageElement` and [`PDPageObjectGroup`](@ref) can be extended by composition. Hence, there are
more specialized objects that can be seen as well.

"""
abstract type PDPageObject end

"""
```
    PDPageElement
```
A representation of a content object with operator and operand. See [`PDPageObject`](@ref)
for more details.
"""
mutable struct PDPageElement{S} <: PDPageObject
    t::Symbol
    version::Tuple{Int,Int}
    noperand::Int
    operands::Vector{CosObject}
end

PDPageElement(ts::AbstractString,ver::Tuple{Int,Int},nop::Int=0)=
  PDPageElement{Symbol(ts)}(Symbol(ts),ver,nop,Vector{CosObject}())

function show(io::IO, e::PDPageElement)
    for op in e.operands
        show(io, op)
        print(io, ' ')
    end
    print(io, String(e.t))
end

"""
```
    PDPageObjectGroup
```
A representation of a content object that encloses other content objects. See
[`PDPageObject`](@ref) for more details.
"""
mutable struct PDPageObjectGroup <: PDPageObject
    isEOG::Bool
    objs::Vector{Union{PDPageObject, CosObject}}
    PDPageObjectGroup(isEOG::Bool=false) =
        new(isEOG, Vector{Union{PDPageObject, CosObject}}())
end

Base.isempty(grp::PDPageObjectGroup) = isempty(grp.objs)

function load_objects(grp::PDPageObjectGroup, bis::IO)
    while(!grp.isEOG && !eof(bis))
        obj = parse_value(bis, get_pdfcontentops)
        collect_object(grp, obj, bis)
    end
end

# Ignore comments in content stream
collect_object(grp::PDPageObjectGroup, obj::CosComment, bis::IO) = nothing

collect_object(grp::PDPageObjectGroup, obj::CosObject, bis::IO) =
    push!(grp.objs, obj)

function populate_element(grp::PDPageObjectGroup, elem::PDPageElement)
    #Find operands for the Operator
    if (elem.noperand >= 0)
        for i=1:elem.noperand
            operand=pop!(grp.objs)
            pushfirst!(elem.operands,operand)
        end
    else
        while(isa(grp.objs[end],CosObject))
            operand=pop!(grp.objs)
            pushfirst!(elem.operands,operand)
        end
    end
end

function collect_object(grp::PDPageObjectGroup, elem::PDPageElement,
                        bis::IO)
    populate_element(grp, elem)
    push!(grp.objs, elem)
    return elem
end

"""
```
    PDPageTextObject
```
A [`PDPageObjectGroup`](@ref) object that represents a block of text. See [`PDPageObject`](@ref)
for more details.
"""
mutable struct PDPageTextObject <: PDPageObject
    group::PDPageObjectGroup
    PDPageTextObject()=new(PDPageObjectGroup())
end

"""
```
    PDPageMarkedContent
```
A [`PDPageObjectGroup`](@ref) object that represents a group of a object that is logically
grouped together in case of a structured PDF document.
"""
mutable struct PDPageMarkedContent <: PDPageObject
    group::PDPageObjectGroup
    PDPageMarkedContent()=new(PDPageObjectGroup())
end

"""
```
    PDPageInlineImage
```
Most images in PDF documents are defined in the PDF document and referenced from the page
content stream. [`PDPageInlineImage`](@ref) objects are directly defined in the page
content stream.
"""
mutable struct PDPageInlineImage <: PDPageObject
    params::CosDict
    data::Vector{UInt8}
    isRead::Bool
    PDPageInlineImage()=new(CosDict(),Vector{UInt8}(),false)
end

function show(io::IO, im::PDPageInlineImage)
    println(io, "BI")
    for (k, v) in get(im.params)
        println("$k $v")
    end
    println("ID")
    println("< $(length(im.data)) bytes... >")
    println(io, "EI")
end

#=
```
    PDPage_BeginInlineImage
```
A [`PDPageElement`](@ref) that represents the beginning of an inline image.
=#
mutable struct PDPage_BeginInlineImage <: PDPageObject
    elem::PDPageElement
    PDPage_BeginInlineImage(ts::AbstractString, ver::Tuple{Int,Int}, nop, ::Type)=
        new(PDPageElement(ts,ver,nop))
end

function collect_object(grp::PDPageObjectGroup, beg::PDPage_BeginInlineImage,
                        bis::IO)
    newobj=PDPageInlineImage()

    while(!newobj.isRead)
        value = parse_value(bis, get_pdfcontentops)
        collect_inline_image(newobj, value, bis)
    end
    push!(grp.objs, newobj)
    return newobj
end

"""
```
    PDPageTextRun
```
In PDF text may not be contiguous as there may be chnge of font, style, graphics rendering
parameters. `PDPageTextRun` is a unit of text which can be rendered without any change to
the graphical parameters. There is no guarantee that a text run will represent a meaningful
word or sentence.

`PDPageTextRun` is a composition implementation of [`PDPageElement`](@ref).
"""
mutable struct PDPageTextRun <: PDPageObject
    ss::Vector{Union{CosXString, CosLiteralString, CosInt, CosFloat}}
    elem::PDPageElement
    PDPageTextRun(ts::AbstractString,ver::Tuple{Int,Int},nop::Int=0) =
        new(Vector{Union{CosXString, CosLiteralString, CosInt, CosFloat}}(),
            PDPageElement(ts, ver, nop))
end

function show(io::IO, tr::PDPageTextRun)
    print(io, "[")
    for s in tr.ss
        print(io, s)
    end
    print(io, "]")
end

function collect_object(grp::PDPageObjectGroup, tr::PDPageTextRun,
                        bis::IO)
    elem = collect_object(grp, tr.elem, bis)
    for operand in elem.operands
        if isa(operand, CosString)
            push!(tr.ss, operand)
        elseif isa(operand, CosArray)
            for td in get(operand)
                push!(tr.ss, td)
            end
        end
    end
    val = pop!(grp.objs)
    push!(grp.objs, tr)
    return tr
end

function collect_inline_image(img::PDPageInlineImage, name::CosName, bis::IO)
    value = parse_value(bis, get_pdfcontentops)
    set!(img.params, name, value)
end

function collect_inline_image(img::PDPageInlineImage, elem::PDPageElement,
                              bis::IO)
    elem.t !== :ID && return img
    while(!img.isRead && !eof(bis))
        b1 = _peekb(bis)
        if (b1 == LATIN_UPPER_E)
            mark(bis)
            skip(bis, 1)
            b2 = _peekb(bis)
            if (b2 == LATIN_UPPER_I)
                skip(bis, 1); b3 = _peekb(bis)
                if (ispdfspace(b3))
                    skip(bis, 1)
                    img.isRead = true
                    unmark(bis)
                    break
                else
                    reset(bis)
                end
            else
                reset(bis)
            end
        end
        push!(img.data, b1)
        skip(bis, 1)
    end
    return img
end

"""
```
    PDPage_BeginGroup
```
A [`PDPageElement`](@ref) that represents the beginning of a group object.
"""
mutable struct PDPage_BeginGroup <: PDPageObject
    elem::PDPageElement
    objT::Type
    PDPage_BeginGroup(ts::AbstractString,ver::Tuple{Int,Int},nop,t::Type) =
        new(PDPageElement(ts,ver,nop),t)
end

"""
```
    PDPage_EndGroup
```
A [`PDPageElement`](@ref) that represents the end of a group object.
"""
mutable struct PDPage_EndGroup
    elem::PDPageElement
    PDPage_EndGroup(ts::AbstractString,ver::Tuple{Int,Int},nop) =
        new(PDPageElement(ts,ver,nop))
end

show(io::IO, e::PDPage_BeginGroup) = show(io, e.elem)

show(io::IO, e::PDPage_EndGroup) = show(io, e.elem)

function collect_object(grp::PDPageObjectGroup, beg::PDPage_BeginGroup,
                        bis::IO)
    populate_element(grp,beg.elem)
    newobj=beg.objT()
    push!(newobj.group.objs,beg.elem)
    load_objects(newobj.group,bis)
    push!(grp.objs, newobj)
    return newobj
end

function collect_object(grp::PDPageObjectGroup, elem::PDPage_EndGroup,
                        bis::IO)
    collect_object(grp,elem.elem,bis)
    grp.isEOG = true
    return grp
end

#=
|Operator|PostScript Equivalent|Description|Table|
|:--------|:----------------------|:------------|------:|
|BX||(PDF 1.1) Begin compatibility section|32|
|EX||(PDF 1.1) End compatibility section|32|
|cm|concat|Concatenate matrix to current transformation matrix|57|
|d|setdash|Set line dash pattern|57|
|gs||(PDF 1.2) Set parameters from graphics state parameter dictionary|57|
|i|setflat|Set flatness tolerance|57|
|j|setlinejoin|Set line join style|57|
|J|setlinecap|Set line cap style|57|
|M|setmiterlimit|Set miter limit|57|
|q|gsave|Save graphics state|57|
|Q|grestore|Restore graphics state|57|
|ri||Set color rendering intent|57|
|w|setlinewidth|Set line width|57|
|c|curveto|Append curved segment to path (three control points)|59|
|h|closepath|Close subpath|59|
|l|lineto|Append straight line segment to path|59|
|m|moveto|Begin new subpath|59|
|re||Append rectangle to path|59|
|v|curveto|Append curved segment to path (initial point replicated)|59|
|y|curveto|Append curved segment to path (final point replicated)|59|
|b|closepath, fill, stroke|Close, fill, and stroke path using nonzero winding number rule|60|
|B|fill, stroke|Fill and stroke path using nonzero winding number rule|60|
|b*|closepath, eofill, stroke|Close, fill, and stroke path using even-odd rule|60|
|B*|eofill, stroke|Fill and stroke path using even-odd rule|60|
|f|fill|Fill path using nonzero winding number rule|60|
|F|fill|Fill path using nonzero winding number rule (obsolete)|60|
|f*|eofill|Fill path using even-odd rule|60|
|n||End path without filling or stroking|60|
|s|closepath, stroke|Close and stroke path|60|
|S|stroke|Stroke path|60|
|W|clip|Set clipping path using nonzero winding number rule|61|
|W*|eoclip|Set clipping path using even-odd rule|61|
|CS|setcolorspace|(PDF 1.1) Set color space for stroking operations|74|
|cs|setcolorspace|(PDF 1.1) Set color space for nonstroking operations|74|
|G|setgray|Set gray level for stroking operations|74|
|g|setgray|Set gray level for nonstroking operations|74|
|K|setcmykcolor|Set CMYK color for stroking operations|74|
|k|setcmykcolor|Set CMYK color for nonstroking operations|74|
|RG|setrgbcolor|Set RGB color for stroking operations|74|
|rg|setrgbcolor|Set RGB color for nonstroking operations|74|
|SC|setcolor|(PDF 1.1) Set color for stroking operations|74|
|sc|setcolor|(PDF 1.1) Set color for nonstroking operations|74|
|SCN|setcolor|(PDF 1.2) Set color for stroking operations\n|||(ICCBased and special colour spaces)|74|
|scn|setcolor|(PDF 1.2) Set color for nonstroking operations\n|||(ICCBased and special colour spaces)|74|
|sh|shfill|(PDF 1.3) Paint area defined by shading pattern|77|
|Do||Invoke named XObject|87|
|BI||Begin inline image object|92|
|EI||End inline image object|92|
|ID||Begin inline image data|92|
|BT||Begin text object|107|
|ET||End text object|107|
|T*||Move to start of next text line|108|
|Td||Move text position|108|
|TD||Move text position and set leading|108|
|Tj|show|Show text|109|
|TJ||Show text, allowing individual glyph positioning|109|
|\'||Move to next line and show text|109|
|\"||Set word and character spacing, move to next line, and show text|109|
|Tc||Set character spacing|105|
|Tf|selectfont|Set text font and size|105|
|TL||Set text leading|105|
|Tr||Set text rendering mode|105|
|Ts||Set text rise|105|
|Tw||Set word spacing|105|
|Tz||Set horizontal text scaling|105|
|d0|setcharwidth|Set glyph width in Type 3 font|113|
|d1|setcachedevice|Set glyph width and bounding box in Type 3 font|113|
|BDC||(PDF 1.2) Begin marked-content sequence with property list|320|
|BMC||(PDF 1.2) Begin marked-content sequence|320|
|DP||(PDF 1.2) Define marked-content point with property list|320|
|EMC||(PDF 1.2) End marked-content sequence|320|
|MP||(PDF 1.2) Define marked-content point|320|
=#
const PD_CONTENT_OPERATORS = Dict(
"\'"=>[PDPageTextRun,"\'",(1,0),1],
"\""=>[PDPageTextRun,"\"",(1,0),3],
"b"=>[PDPageElement,"b",(1,0),0],
"b*"=>[PDPageElement,"b*",(1,0),0],
"B"=>[PDPageElement,"B",(1,0),0],
"B*"=>[PDPageElement,"B*",(1,0),0],
"BDC"=>[PDPage_BeginGroup,"BDC",(1,2),2,PDPageMarkedContent],
"BI"=>[PDPage_BeginInlineImage,"BI",(1,0),0,PDPageInlineImage],
"BMC"=>[PDPage_BeginGroup,"BMC",(1,2),1,PDPageMarkedContent],
"BT"=>[PDPage_BeginGroup,"BT",(1,0),0,PDPageTextObject],
"BX"=>[PDPageElement,"BX",(1,1),0],
"c"=>[PDPageElement,"c",(1,0),6],
"cm"=>[PDPageElement,"cm",(1,0),6],
"cs"=>[PDPageElement,"cs",(1,1),1],
"CS"=>[PDPageElement,"CS",(1,1),1],
"d"=>[PDPageElement,"d",(1,0),2],
"d0"=>[PDPageElement,"d0",(1,0),2],
"d1"=>[PDPageElement,"d1",(1,0),6],
"Do"=>[PDPageElement,"Do",(1,0),1],
"DP"=>[PDPageElement,"DP",(1,2),0],
"EI"=>[PDPageElement,"EI",(1,0),0],
"EMC"=>[PDPage_EndGroup,"EMC",(1,2),0],
"ET"=>[PDPage_EndGroup,"ET",(1,0),0],
"EX"=>[PDPageElement,"EX",(1,1),0],
"f"=>[PDPageElement,"f",(1,0),0],
"f*"=>[PDPageElement,"f*",(1,0),0],
"F"=>[PDPageElement,"F",(1,0),0],
"g"=>[PDPageElement,"g",(1,0),1],
"G"=>[PDPageElement,"G",(1,0),1],
"gs"=>[PDPageElement,"gs",(1,2),1],
"h"=>[PDPageElement,"h",(1,0),0],
"i"=>[PDPageElement,"i",(1,0),1],
"ID"=>[PDPageElement,"ID",(1,0),0],
"j"=>[PDPageElement,"j",(1,0),1],
"J"=>[PDPageElement,"J",(1,0),1],
"k"=>[PDPageElement,"k",(1,0),4],
"K"=>[PDPageElement,"K",(1,0),4],
"l"=>[PDPageElement,"l",(1,0),2],
"m"=>[PDPageElement,"m",(1,0),2],
"M"=>[PDPageElement,"M",(1,0),1],
"MP"=>[PDPageElement,"MP",(1,2),0],
"n"=>[PDPageElement,"n",(1,0),0],
"q"=>[PDPageElement,"q",(1,0),0],
"Q"=>[PDPageElement,"Q",(1,0),0],
"re"=>[PDPageElement,"re",(1,0),4],
"rg"=>[PDPageElement,"rg",(1,0),3],
"RG"=>[PDPageElement,"RG",(1,0),3],
"ri"=>[PDPageElement,"ri",(1,0),1],
"s"=>[PDPageElement,"s",(1,0),0],
"S"=>[PDPageElement,"S",(1,0),0],
"sc"=>[PDPageElement,"sc",(1,1),-1],
"SC"=>[PDPageElement,"SC",(1,1),-1],
"scn"=>[PDPageElement,"scn",(1,2),-1],
"SCN"=>[PDPageElement,"SCN",(1,2),-1],
"sh"=>[PDPageElement,"sh",(1,3),1],
"T*"=>[PDPageElement,"T*",(1,0),0],
"Tc"=>[PDPageElement,"Tc",(1,0),1],
"Td"=>[PDPageElement,"Td",(1,0),2],
"TD"=>[PDPageElement,"TD",(1,0),2],
"Tf"=>[PDPageElement,"Tf",(1,0),2],
"Tj"=>[PDPageTextRun,"Tj",(1,0),1],
"TJ"=>[PDPageTextRun,"TJ",(1,0),1],
"TL"=>[PDPageElement,"TL",(1,0),1],
"Tm"=>[PDPageElement,"Tm",(1,0),6],
"Tr"=>[PDPageElement,"Tr",(1,0),1],
"Ts"=>[PDPageElement,"Ts",(1,0),1],
"Tw"=>[PDPageElement,"Tw",(1,0),1],
"Tz"=>[PDPageElement,"Tz",(1,0),1],
"v"=>[PDPageElement,"v",(1,0),4],
"w"=>[PDPageElement,"w",(1,0),1],
"W"=>[PDPageElement,"W",(1,0),0],
"W*"=>[PDPageElement,"W*",(1,0),0],
"y"=>[PDPageElement,"y",(1,0),4]
)

function get_pdfcontentops(b::Vector{UInt8})
    # PDF content operators are never longer than 3 bytes and may not be
    # delimited. Hence, search for the longest 3 byte keyword, then 2 bytes
    # and lastly 1
    arr, l, sb = nothing, length(b), b
    if l > 3
        sb, l = b[1:3], 3
    end
    s = l
    while arr == nothing && s > 0
        arr = get(PD_CONTENT_OPERATORS, String(sb[1:s]), nothing)
        s -= 1
    end
    if arr !== nothing
        return s+1, eval(Expr(:call, arr...))
    end
    error("Invalid content operator: $(String(b))")
end

struct TextLayout
    lbx::Float32
    lby::Float32
    rbx::Float32
    rby::Float32
    rtx::Float32
    rty::Float32
    ltx::Float32
    lty::Float32
    text::String
    fontname::CosName
    fontflags::UInt32
end

CDRect(t::TextLayout) = CDRect(min(t.lbx, t.rbx, t.rtx, t.ltx),
                               min(t.lby, t.rby, t.rty, t.lty),
                               max(t.lbx, t.rbx, t.rtx, t.ltx),
                               max(t.lby, t.rby, t.rty, t.lty))

@inline function width(tl)
    dx = tl.rbx - tl.lbx; dy = tl.rby - tl.lby
    return sqrt(dx*dx + dy*dy)
end

@inline function height(tl)
    dx = tl.ltx - tl.lbx; dy = tl.lty - tl.lby
    return sqrt(dx*dx + dy*dy)
end

Base.:>(tl1::TextLayout, tl2::TextLayout) = Base.isless(tl2, tl1)

@inline function Base.isless(tl1::TextLayout, tl2::TextLayout)
    y2 = max(tl2.lby, tl2.rby, tl2.rty, tl2.lty)
    x2 = min(tl2.lbx, tl2.rbx, tl2.rtx, tl2.ltx)

    y1 = max(tl1.lby, tl1.rby, tl1.rty, tl1.lty)
    x1 = min(tl1.lbx, tl1.rbx, tl1.rtx, tl1.ltx)

    dy = y1 - y2
    dx = x1 - x2
    # This will ensure superscripts with smaller fonts where baseline
    # shift is less than half the height of the baseline fonts is aligned
    # to current line and not an additional line above
    ytol1 = (tl1.lty - tl1.lby)/2
    ytol2 = (tl2.lty - tl2.lby)/2
    ytol = abs(ytol1) > abs(ytol2) ? ytol1 : ytol2
    dy < -ytol && return true
    dy >  ytol && return false
    return dx > 0
end

# using DataStructures

mutable struct GState{T}
    state::Vector{Dict{Symbol, Any}}
    GState{T}() where T = new(init_graphics_state())
end

new_gstate(state::GState{T}) where T = GState{T}()
Base.setindex!(gs::GState, v::V, k::Symbol) where V = (gs.state[end][k] = v)
Base.get(gs::GState, k::Symbol, R::Type) = gs.state[end][k]::R
Base.get(gs::GState, k::Symbol, defval::S, R::Type=S) where S  =
    get(gs.state[end], k, defval)::Union{R, S}
Base.get!(gs::GState, k::Symbol, defval::S, R::Type=S) where S =
    get!(gs.state[end], k, defval)::Union{R, S}
Base.delete!(gs::GState, k::Symbol) = delete!(gs.state[end], k)
save!(gs::GState) = (push!(gs.state, copy(gs.state[end])); gs)
restore!(gs::GState) = (pop!(gs.state); gs)

@inline function init_graphics_state()
    state = Vector{Dict{Symbol, Any}}(undef, 0)
    push!(state, Dict{Symbol, Any}())
    
    state[end][:text_layout] = Vector{TextLayout}()

    # Histogram along the y-axis. Not used currently.
    state[end][:h_profile] = Dict{Int,Int}()

    # Graphics state
    state[end][:CTM] = Matrix{Float32}(I, 3, 3)

    # Text states
    state[end][:Tc] = 0f0
    state[end][:Tw] = 0f0
    state[end][:Tz] = 100f0
    state[end][:TL] = 0f0
    state[end][:Tr] = 0
    state[end][:Ts] = 0f0
    return state
end

function show_text_layout!(io::IO, state::GState)
    #Make sure to deepcopy. Otherwise the data structures will be lost
    heap = get(state, :text_layout, Vector{TextLayout})
    sort!(heap, lt= > )
    szdict = get(state, :h_profile, Dict{Int, Int})

    x = 0f0
    y = -1f0

    pairs = sort(collect(szdict), lt=(x,y)->(x[2] > y[2]))
    length(pairs) == 0 && return io
    iht, num = pairs[1]
    ht = iht*0.1f0

    # Courier font X width is 600 
    xwr = 0.6f0
    ph = 0f0
    npc = 0
    for i = 1:lastindex(heap)
        tlayout = heap[i]
        h = height(tlayout)
        if h > 7f0*ht
            ht = h
        end
        xw = xwr*ht
        nc = length(tlayout.text)
        w = width(tlayout)/nc
        @assert w > 0.1f0
        @assert h > 0.1f0
        if (ht > h)
            while (y > tlayout.lty)
                print(io, '\n')
                y -= ht
                x = 0f0
            end
        else
            while (y > tlayout.lby + ht)
                print(io, '\n')
                y -= ht
                x = 0f0
            end
            y = tlayout.lby
        end
        y = tlayout.lby
        # For subscripts and superscripts insert a space on both sides
        # However, ignore the same for dropcaps.
        (x > tlayout.lbx - xw) && (ph < h || (ph > h && npc > 1)) && print(io, ' ')
        while x < tlayout.lbx - xw
            print(io, ' ')
            x += xw
        end
        x = tlayout.lbx
        print(io, tlayout.text)
        x += width(tlayout)
        while x < tlayout.rbx - xw
            print(io, ' ')
            x += xw
        end
        x = tlayout.rbx
        ph = h
        npc = nc
    end
    return io
end

@inline function evalContent!(grp::PDPageObjectGroup, state::GState)
    for obj in grp.objs
        evalContent!(obj, state)
    end
    return state
end

function eval_unicode_mapping(tr::PDPageTextRun, state::GState)
    fontname, font = get(state, :font, (cn"", CosNull), Tuple{CosName, PDFont})
    if font.fum === nothing
        src = get(state, :source, nothing, Union{PDPage, PDXObject})
        src === nothing && error("Graphics state :source is not configured")
        warn_no_unicode_mapping(src, font, fontname)
        @warn "Text run $tr may be decoded as ASCII"
    end
    return fontname, font
end

function warn_no_unicode_mapping(page::PDPage, font, fontname)
    pageno = pdPageGetPageNumber(page)
    @warn "No unicode mapping for font $fontname at Page $pageno"
end

function warn_no_unicode_mapping(xo::PDXObject, font, fontname)
    ref = CosIndirectObjectRef(xo.cosXObj.num, xo.cosXObj.gen)
    @warn "No unicode mapping for font $fontname at XObject at $ref"
end

@inline function evalContent!(tr::PDPageTextRun, state::GState)
    evalContent!(tr.elem, state)
    tfs = get(state, :fontsize, 0f0)
    th  = get(state, :Tz, Float32)/100f0
    ts  = get(state, :Ts, Float32)
    tc  = get(state, :Tc, Float32)
    tw  = get(state, :Tw, Float32)
    tm  = get(state, :Tm, Matrix{Float32})
    ctm = get(state, :CTM, Matrix{Float32})
    trm = tm*ctm

    fontname, font = eval_unicode_mapping(tr, state)
    
    heap = get(state, :text_layout, Vector{TextLayout})
    text, w, h = get_TextBox(tr.ss, font, tfs, tc, tw, th)

    d = get(state, :h_profile, Dict{Int, Int})
    ih = round(Int, h*10)
    d[ih] = get(d, ih, 0) + length(text)

    tb = [0f0 0f0 1f0; w 0f0 1f0; w h 1f0; 0f0 h 1f0]*trm
    if !get(state, :in_artifact, false)
        tl = TextLayout(tb[1,1], tb[1,2], tb[2,1], tb[2,2],
                        tb[3,1], tb[3,2], tb[4,1], tb[4,2],
                        text, fontname, font.flags)
        push!(heap, tl)
    end
    offset_text_pos!(w, 0f0, state)    
    return state
end

@inline function evalContent!(pdo::PDPageTextObject,
                              state::GState)
    state[:Tm]  = Matrix{Float32}(I, 3, 3)
    state[:Tlm] = Matrix{Float32}(I, 3, 3)
    state[:Trm] = Matrix{Float32}(I, 3, 3)
    evalContent!(pdo.group, state)
    delete!(state, :Tm)
    delete!(state, :Tlm)
    delete!(state, :Trm)
    return state
end

@inline function evalContent!(pdo::PDPageMarkedContent, state::GState)
    tag = pdo.group.objs[1].operands[1] # can be used for XML tagging.
    if tag == cn"Artifact"
        state[:in_artifact] = true
        evalContent!(pdo.group, state)
        delete!(state, :in_artifact)
        return state
    end
    return evalContent!(pdo.group, state)
end

evalContent!(pdo::PDPageElement{S}, state::GState) where S = state

evalContent!(pdo::PDPageElement{:q}, state::GState) = save!(state)

evalContent!(pdo::PDPageElement{:Q}, state::GState) = restore!(state)

@inline function evalContent!(pdo::PDPageElement{:cm}, state::GState)
    a = get(pdo.operands[1])
    b = get(pdo.operands[2])
    c = get(pdo.operands[3])
    d = get(pdo.operands[4])
    e = get(pdo.operands[5])
    f = get(pdo.operands[6])
    cm  = [a b 0f0; c d 0f0; e f 1f0]
    ctm = get(state, :CTM, Matrix{Float32})
    ctm = cm*ctm
    state[:CTM] = ctm
    return state
end

@inline function evalContent!(pdo::PDPageElement{:Tm}, state::GState)
    a = get(pdo.operands[1])
    b = get(pdo.operands[2])
    c = get(pdo.operands[3])
    d = get(pdo.operands[4])
    e = get(pdo.operands[5])
    f = get(pdo.operands[6])
    tm  = [a b 0f0; c d 0f0; e f 1f0]
    tlm = copy(tm)
    state[:Tm]  = tm
    state[:Tlm] = tlm
    return state
end

@inline function evalContent!(pdo::PDPageElement{:Tf}, state::GState)
    src = get(state, :source, Union{PDPage, PDXObject})
    fontname = pdo.operands[1]
    font = get_font(src, fontname)
    font === CosNull && return state
    state[:font] = (fontname, font)
    fontsize = get(pdo.operands[2])
    # PDF Spec expects any number so better to standardize to Float32
    state[:fontsize] = Float32(fontsize)
    return state
end

# PDF Spec expects any number so better to standardize to Float32
for op in ["Tc", "Tw", "Tz", "TL", "Tr", "Ts"]
    @eval evalContent!(pdo::PDPageElement{Symbol($op)}, state::GState) =
        (state[Symbol($op)] = Float32(get(pdo.operands[1])); state)
end

@inline function set_text_pos!(tx, ty, state::GState)
    tmul = [1f0 0f0 0f0; 0f0 1f0 0f0; tx ty 1f0]
    #:TL may be called outside of BT...ET block
    tlm = get(state, :Tlm, Matrix{Float32}(I, 3, 3))
    tlm = tmul*tlm
    tm = copy(tlm)

    state[:Tm]  = tm
    state[:Tlm] = tlm
    return state
end

# Affects Tm leaves the Tlm intact
@inline function offset_text_pos!(tx, ty, state::GState)
    tmul = [1f0 0f0 0f0; 0f0 1f0 0f0; tx ty 1f0]
    #:TL may be called outside of BT...ET block
    tm = get(state, :Tm, Matrix{Float32}(I, 3, 3))
    tm = tmul*tm
    state[:Tm]  = tm
    return state
end

@inline function offset_text_leading!(state::GState)
    tl = get(state, :TL, Float32)
    return set_text_pos!(0f0, -tl, state)
end

@inline function evalContent!(pdo::PDPageElement{:TD}, state::GState)
    tx = Float32(get(pdo.operands[1]))
    ty = Float32(get(pdo.operands[2]))

    state[:TL] = -ty
    set_text_pos!(tx, ty, state)
end

@inline function evalContent!(pdo::PDPageElement{:Td}, state::GState)
    tx = Float32(get(pdo.operands[1]))
    ty = Float32(get(pdo.operands[2]))

    set_text_pos!(tx, ty, state)
end

evalContent!(pdo::PDPageElement{Symbol("T*")}, state::GState) =
    offset_text_leading!(state)

evalContent!(pdo::PDPageElement{Symbol("\'")}, state::GState) =
    offset_text_leading!(state)

@inline function evalContent!(pdo::PDPageElement{Symbol("\"")}, state::GState)#" 
    state[:Tw] = Float32(get(pdo.operands[1]))
    state[:Tc] = Float32(get(pdo.operands[2]))
    offset_text_leading!(state)
end

function evalContent!(pdo::PDPageElement{:Do}, state::GState)
    xobjname = pdo.operands[1]
    src = get(state, :source, Union{PDPage, PDXObject})
    xobj = get_xobject(src, xobjname)
    xobj === CosNull && return state
    return Do(xobj, state)
end

evalContent!(pdo::PDPageInlineImage, state::GState) = state

evalContent!(pdo::CosObject, state::GState) = state
