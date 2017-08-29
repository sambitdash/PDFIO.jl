using BufferedStreams
import Base: show

abstract type PDPageObject end

"""
*PDPageElement* type is a representation of organization of content and content
operators.

The operands are like attributes of the element to be used for any operations.
"""
mutable struct PDPageElement <: PDPageObject
    t::Symbol
    version::Tuple{Int,Int}
    noperand::Int
    operands::Vector{CosObject}
end

PDPageElement(ts::AbstractString,ver::Tuple{Int,Int},nop::Int=0)=
  PDPageElement(Symbol(ts),ver,nop,Vector{CosObject}())

function show(io::IO, e::PDPageElement)
    for op in e.operands
        show(io, op)
        print(io, ' ')
    end
    print(io, String(e.t))
end

mutable struct PDPageObjectGroup <: PDPageObject
    isEOG::Bool
    objs::Vector{Union{PDPageObject,CosObject}}
    PDPageObjectGroup(isEOG::Bool=false) =
        new(isEOG,Vector{Union{PDPageObject,CosObject}}())
end

function load_objects(grp::PDPageObjectGroup, bis::BufferedInputStream)
    while(!grp.isEOG && !eof(bis))
        obj = parse_value(bis)
        collect_object(grp, obj, bis)
    end
end

collect_object(grp::PDPageObjectGroup, obj::CosObject, bis::BufferedInputStream) =
    push!(grp.objs, obj)

function populate_element(grp::PDPageObjectGroup, elem::PDPageElement)
    #Find operands for the Operator
    if (elem.noperand >= 0)
        for i=1:elem.noperand
            operand=pop!(grp.objs)
            unshift!(elem.operands,operand)
        end
    else
        len=endof(grp.objs)
        while(isa(grp.objs[len],CosObject))
            operand=pop!(grp.objs)
            unshift!(elem.operands,operand)
            len = endof(grp.objs)
        end
    end
end

function collect_object(grp::PDPageObjectGroup, elem::PDPageElement,
                        bis::BufferedInputStream)
    populate_element(grp,elem)
    push!(grp.objs, elem)
    return elem
end

mutable struct PDPageTextObject <: PDPageObject
    group::PDPageObjectGroup
    PDPageTextObject()=new(PDPageObjectGroup())
end

mutable struct PDPageMarkedContent <: PDPageObject
    group::PDPageObjectGroup
    PDPageMarkedContent()=new(PDPageObjectGroup())
end

mutable struct PDPageInlineImage <: PDPageObject
    params::CosDict
    data::Vector{UInt8}
    isRead::Bool
    PDPageInlineImage()=new(CosDict(),Vector{UInt8}(),false)
end

mutable struct PDPage_BeginInlineImage <: PDPageObject
    elem::PDPageElement
    PDPage_BeginInlineImage(ts::AbstractString,ver::Tuple{Int,Int},nop)=
        new(PDPageElement(ts,ver,nop))
end

function collect_object(grp::PDPageObjectGroup, beg::PDPage_BeginInlineImage,
                        bis::BufferedInputStream)
    newobj=PDPageInlineImage()

    while(!newobj.isRead)
        value=parse_value(bis)
        collect_inline_image(img,value,bis)
    end
    push!(grp.objs, newobj)
    return newobj
end

mutable struct PDPageTextRun <: PDPageObject
    ss::Vector{CosString}
    elem::PDPageElement
    PDPageTextRun(ts::AbstractString,ver::Tuple{Int,Int},nop::Int=0) =
        new(Vector{String}(), PDPageElement(ts, ver, nop))
end

show(io::IO, tr::PDPageTextRun) = show(io, tr.ss)

function collect_object(grp::PDPageObjectGroup, tr::PDPageTextRun,
                        bis::BufferedInputStream)
    elem = collect_object(grp, tr.elem, bis)
    for operand in elem.operands
        if isa(operand, CosString)
            push!(tr.ss, operand)
        elseif isa(operand, CosArray)
            for td in get(operand)
                if isa(td, CosString)
                    push!(tr.ss, td)
                end
            end
        end
    end
    val = pop!(grp.objs)
    push!(grp.objs, tr)
    return tr
end



function collect_inline_image(img::PDPageInlineImage, name::CosName,
    bis::BufferedInputStream)
    value = parse_value(bis)
    set!(img.params, name, value)
end

function collect_inline_image(img::PDPageInlineImage, elem::PDPageElement,
                              bis::BufferedInputStream)
    if (elem.t == Symbol("ID"))
        while(!image.isRead && !eof(bis))
            b1 = peek(bis)
            if (b1 == LATIN_E)
                mark(bis)
                skip(bis,1);
                b2 = peek(bis)
                if (b2 == LATIN_I)
                    skip(bis,1);b3 = peek(bis)
                    if (is_crorlf(b3))
                        skip(bis,1)
                        img.isRead=true
                        unmark(s)
                        break
                    else
                        reset(bis)
                    end
                else
                    reset(bis)
                end
            end
            push!(img.data, b1)
            skip(bis,1);
        end
    end
    return img
end


mutable struct PDPage_BeginGroup <: PDPageObject
    elem::PDPageElement
    objT::Type
    PDPage_BeginGroup(ts::AbstractString,ver::Tuple{Int,Int},nop,t::Type) =
        new(PDPageElement(ts,ver,nop),t)
end

mutable struct PDPage_EndGroup
    elem::PDPageElement
    PDPage_EndGroup(ts::AbstractString,ver::Tuple{Int,Int},nop) =
        new(PDPageElement(ts,ver,nop))
end

show(io::IO, e::PDPage_BeginGroup) = show(io, e.elem)

show(io::IO, e::PDPage_EndGroup) = show(io, e.elem)

function collect_object(grp::PDPageObjectGroup, beg::PDPage_BeginGroup,
                        bis::BufferedInputStream)
    populate_element(grp,beg.elem)
    newobj=beg.objT()
    push!(newobj.group.objs,beg.elem)
    load_objects(newobj.group,bis)
    push!(grp.objs, newobj)
    return newobj
end

function collect_object(grp::PDPageObjectGroup, elem::PDPage_EndGroup,
                        bis::BufferedInputStream)
    collect_object(grp,elem.elem,bis)
    grp.isEOG = true
    return grp
end

"""
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
"""
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

import ..Cos: get_pdfcontentops

function get_pdfcontentops(b::Vector{UInt8})
    arr = get(PD_CONTENT_OPERATORS, String(b), CosNull)
    if (arr == CosNull)
        return CosNull
    else
        return eval(Expr(:call,arr...))
    end
end

function showtext(io::IO, grp::PDPageObjectGroup)
    for obj in grp.objs
        showtext(io, obj)
    end
    return io
end

function showtext(io::IO, tr::PDPageTextRun)
    for s in tr.ss
        cdtext = CDTextString(s)
        write(io, cdtext)
    end
    return io
end

showtext(io::IO, pdo::PDPageTextObject) = showtext(io, pdo.group)

function showtext(io::IO, pdo::PDPageMarkedContent)
    tag = pdo.group.objs[1].operands[1] # can be used for XML tagging. 
    showtext(io, pdo.group)
    write(io, '\n')
end

showtext(io::IO, pdo::PDPageElement) = io

showtext(io::IO, pdo::CosObject) = show(io, pdo)
