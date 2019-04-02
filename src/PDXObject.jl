abstract type PDXObject end

mutable struct PDFormXObject <: PDXObject
    doc::PDDoc
    cosXObj::CosIndirectObject{CosStream}
    matrix::Matrix{Float32}
    bbox::CDRect{Float32}
    fonts::Dict{CosName, PDFont}
    xobjs::Dict{CosName, PDXObject}
    content_objects::PDPageObjectGroup
    function PDFormXObject(doc::PDDoc, cosxobj::CosIndirectObject{CosStream})
        mat = get(cosxobj, cn"Matrix")
        box = get(cosxobj, cn"BBox")
        @assert box !== CosNull "Invalid Form XObject without bounding box"
        matrix = mat === CosNull ?
            [1f0 0f0 0f0; 0f0 1f0 0f0; 0f0 0f0 1f0] :
            hcat(reshape((get.(CosFloat.(get(mat)))), (2, 3))', [0f0, 0f0, 1f0])
        bbox = CDRect{Float32}(CDRect(box))
        fonts = Dict{CosName, PDFont}()
        xobjs = Dict{CosName, PDXObject}()
        new(doc, cosxobj, matrix, bbox, fonts, xobjs, PDPageObjectGroup())
    end
end

mutable struct PDImageXObject <: PDXObject
    doc::PDDoc
    obj::CosIndirectObject{CosStream}
end

mutable struct PDDefaultXObject <: PDXObject
    doc::PDDoc
    obj::IDD{CosDict}
end

function createPDXObject(doc::PDDoc,
                         cossd::Union{CosIndirectObject{CosStream},
                                      IDD{CosDict}})
    otype = get(cossd, cn"Type")
    @assert otype === cn"XObject" || otype === CosNull
    subtype = get(cossd, cn"Subtype")
    subtype === cn"Form"  && return PDFormXObject(doc, cossd)
    subtype === cn"Image" && return PDImageXObject(doc, cossd)
    return PDDefaultXObject(doc, cossd)
end

function find_resource(xobj::PDFormXObject,
                       restype::CosName,
                       resname::CosName)
    cosdoc = xobj.doc.cosDoc
    resref = get(xobj.cosXObj, cn"Resources")
    resref === CosNull && return CosNull
    resources = cosDocGetObject(cosdoc, resref)
    resources === CosNull && return CosNull
    ress = cosDocGetObject(cosdoc, resources, restype)
    ress === CosNull && return CosNull
    res = cosDocGetObject(cosdoc, ress, resname)
    return res
end

get_font(xobj::PDXObject, fontname::CosName) = 
    get!(xobj.fonts, fontname,
         get_pd_font!(xobj.doc, find_resource(xobj, cn"Font", fontname)))

get_xobject(xobj::PDXObject, xobjname::CosName) = 
    get!(xobj.xobjs, xobjname,
         get_pd_xobject!(xobj.doc,
                         find_resource(xobj, cn"XObject", xobjname)))

function load_content_objects(xobj::PDFormXObject)
    stm = xobj.cosXObj
    bufstm = decode(stm)
    # try
        load_objects(xobj.content_objects, bufstm)
    # finally
    #    util_close(bufstm)
    # end
    return nothing
end

Do(xobj::PDDefaultXObject, state::GState) = nothing

Do(xobj::PDImageXObject, state::GState) = nothing

function Do(xobj::PDFormXObject, state::GState)
    isempty(xobj.content_objects) && load_content_objects(xobj)
    isempty(xobj.content_objects) && return state
    xstate = new_gstate(state)
    ctm = state[:CTM]
    nctm = xobj.matrix*ctm
    xstate[:CTM] = nctm
    xstate[:source] = xobj
    xstate[:text_layout] = state[:text_layout]
    xstate[:h_profile] = state[:h_profile]
    evalContent!(xobj.content_objects, xstate)
    return state
end
