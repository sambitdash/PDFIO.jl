struct CryptParams
    num::Int
    gen::Int
    cfn::CosName
end

decrypt!(::Union{Nothing, SecHandler}, obj) = obj

# Even when document has no security handler the object stream needs to be
# decoded and all the objects and their positions are to be loaded.
function decrypt!(h::Nothing, oi::CosIndirectObject{CosObjectStream})
    obj = oi.obj
    obj.populated && return oi
    cosStreamRemoveFilters(obj.stm)
    read_object_info_from_stm(obj.stm, obj.oids, obj.oloc, obj.n, obj.first)
    obj.populated = true
    return oi
end

function decrypt!(h::SecHandler, oi::CosIndirectObject{CosObjectStream})
    oi.obj.stm = decrypt(h, CryptParams(h, oi), oi.obj.stm)
    return invoke(decrypt!, Tuple{Nothing, CosIndirectObject{CosObjectStream}},
                  nothing, oi)
end

decrypt!(h::SecHandler, oi::CosIndirectObject{CosStream}) = 
    (oi.obj = decrypt(h, CryptParams(h, oi), oi.obj);  oi)

# For Crypt filter chain ensure the filters before the crypt filters are removed.
# Crypt filter parameters are associated with the document and the CosStream as
# such may not have access to such parameters. Hence, the crypt filter has to be
# decrypted when the document information is available.
function decrypt(h::SecHandler, params::CryptParams, o::CosStream)
    # If the stream is external to the PDF file then it's not encrypted
    !o.isInternal && return o
    f = String(get(o, cn"F"))
    len = get(get(o, cn"Length"))
    io = util_open(f, "r")
    ctext = read(io, len)
    util_close(io)
    rm(f) # Not unsafe as decryption is carried out before attaching temp files
    (path, io) = get_tempfilepath()
    try
        ptext = crypt(h, params, ctext, false)
        write(io, ptext)
    finally
        util_close(io)
    end
    set!(o, cn"F", CosLiteralString(path))
    set!(o, cn"Length", CosInt(len))

    filters = get(o, cn"FFilter")
    if filters !== CosNull
        if filters isa CosName
            if cn"Crypt" === filters
                set!(o, cn"FFilter", CosNull)
                set!(o, cn"FDecodeParms", CosNull)
            end
        else
            vf = get(filters)
            l = length(vf)
            if vf[1] === cn"Crypt"
                if l == 1
                    set!(o, cn"FFilter", CosNull)
                    set!(o, cn"FDecodeParms", CosNull)
                else
                    filters = get(o, cn"FFilter")
                    deleteat!(get(filters), 1)
                    params = get(o, cn"FDecodeParms")
                    params !== CosNull && deleteat!(get(params), 1)
                end
            end
        end
    end
    
    o.isInternal = false
    return o
end

function decrypt!(h::SecHandler, oi::Union{ID{CosXString}, ID{CosLiteralString}})
    oi.obj = decrypt(h, CryptParams(h, oi), oi.obj)
    return oi
end

decrypt(h::SecHandler, params::CryptParams, s::CosLiteralString) = 
    crypt(h, params, Vector{UInt8}(s), false) |> CosLiteralString

decrypt(h::SecHandler, params::CryptParams, s::CosXString) = 
    crypt(h, params, Vector{UInt8}(s), false) |>
        bytes2hex |> Vector{UInt8} |> CosXString

function decrypt!(h::SecHandler, oi::Union{ID{CosArray}, ID{CosDict}})
    oi.obj = decrypt(h, oi.num, oi.gen, oi.obj)
    return oi
end
    
function decrypt(h::SecHandler, num::Int, gen::Int, a::CosArray)
    v = get(a)
    for i = 1:length(v)
        v[i] = decrypt(h, num, gen, v[i])
    end
    return a
end

function decrypt(h::SecHandler, num::Int, gen::Int, o::CosDict)
    d = get(o)
    for (k, v) in d
        v1 = decrypt(h, num, gen, v)
        v1 === v && continue
        d[k] = v1
    end
    return o
end

decrypt(h::SecHandler, num::Int, gen::Int, s::CosString) = 
    decrypt(h, CryptParams(h, num, gen, s), s)

decrypt(h::SecHandler, num::Int, gen::Int, o::CosObject) = o
