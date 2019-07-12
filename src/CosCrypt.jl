using Base: SecretBuffer, SecretBuffer!, shred!
import ..Common: decrypt

function store_key(s::SecHandler, cfn::CosName,
                   data::Tuple{UInt32, SecretBuffer})
    skey = SecretBuffer!(read(s.skey_path, 32))
    iv   = SecretBuffer!(read(s.iv_path, 16))
    cctx = CipherContext("aes_256_cbc", skey, iv, true)
    shred!(skey); shred!(iv)

    perm, key = data
    c = update!(cctx, key)
    append!(c, close(cctx))
    s.keys[cfn] = (perm, c)
    return data
end

function get_key(s::SecHandler, cfn::CosName)
    permkey = get(s.keys, cfn, nothing)
    permkey === nothing && return nothing
    
    skey = SecretBuffer!(read(s.skey_path, 32))
    iv   = SecretBuffer!(read(s.iv_path, 16))
    cctx = CipherContext("aes_256_cbc", skey, iv, false)
    shred!(skey); shred!(iv)
    
    perm, c = permkey
    b = update!(cctx, c)
    append!(b, close(cctx))
    return perm, SecretBuffer!(b)
end

function get_cfm(h::SecHandler, cfn::CosName)
    cfn === cn"Identity" && return cn"None"
    cfm = get(get(h.cf, cfn), cn"CFM")
    cfm in [cn"None", cn"V2", cn"AESV2", cn"AESV3"] || error(E_INVALID_CRYPT)
    return cfm
end

struct CryptParams
    num::Int
    gen::Int
    cfn::CosName
end

CryptParams(h::SecHandler, oi::CosIndirectObject) = 
    CryptParams(h, oi.num, oi.gen, oi.obj)

CryptParams(h::SecHandler, num::Int, gen::Int, o::CosObject) =
    h.r < 4 ? CryptParams(num, gen, cn"StdCF") : error(E_INVALID_OBJECT)

CryptParams(h::SecHandler, num::Int, gen::Int, o::CosString) =
    CryptParams(num, gen, h.strf)

CryptParams(h::SecHandler, num::Int, gen::Int, o::CosObjectStream) =
    CryptParams(h, num, gen, o.stm)

# For Crypt filter chain ensure the filters before the crypt filters are removed.
# Crypt filter parameters are associated with the document and the CosStream as
# such may not have access to such parameters. Hence, the crypt filter has to be
# decrypted when the document information is available.
function CryptParams(h::SecHandler, num::Int, gen::Int, o::CosStream)
    cfn = h.stmf
    filters = get(o, cn"FFilter")
    filters === CosNull && return CryptParams(num, gen, cfn)
    if cn"Crypt" === filters ||
        (filters isa CosArray && length(filters) > 0 && cn"Crypt" === filters[1])
        params = get(o, cn"FDecodeParms", CosDict())
        param = params isa CosDict ? params : params[1]
        cfn = get(param, cn"Name", cn"Identity")
    end
    return CryptParams(num, gen, cfn)
end

function get_key(h::SecHandler, params::CryptParams)
    vpw = get_key(h, params.cfn)
    vpw === nothing || return vpw
    return get_key(h, params.cfn, h.access)
end

function algo01(h::SecHandler, params::CryptParams,
                data::AbstractVector{UInt8}, isencrypt::Bool)
    num, gen, cfn = params.num, params.gen, params.cfn
    cfm = get_cfm(h, cfn)
    isRC4 = cfm === cn"V2"
    numarr = copy(reinterpret(UInt8, [num]))
    ENDIAN_BOM == 0x01020304 && reverse!(numarr)
    numarr = numarr[1:3]
    genarr = copy(reinterpret(UInt8, [gen]))
    ENDIAN_BOM == 0x01020304 && reverse!(genarr)
    genarr = genarr[1:2]
    perm, key = get_key(h, params)
    n = div(h.length, 8)
    md = shred!(key) do kc
        n != kc.size && error("Invalid encryption key length")
        seekend(kc); write(kc, numarr); write(kc, genarr)
        !isRC4 && write(kc, AES_SUFFIX)
        mdctx = DigestContext("md5")
        update!(mdctx, kc)
        return close(mdctx)
    end
    l = min(n+5, 16)
    key = SecretBuffer!(md[1:l])
    iv = SecretBuffer!(isRC4 ?     UInt8[] :
                       isencrypt ? crypto_random(16) : data[1:16])
    try
        cctx = CipherContext(isRC4 ? "rc4" : "aes_128_cbc", key, iv, isencrypt)
        d = (isRC4 || isencrypt) ? update!(cctx, data) :
            update!(cctx, (@view data[17:end]))
        append!(d, close(cctx))
        return d
    finally
        shred!(key); shred!(iv)
    end
 end

function algo01a(h::SecHandler, params::CryptParams,
                 data::AbstractVector{UInt8}, isencrypt::Bool)
    perm, key = get_key(h, params)
    iv = SecretBuffer!(isencrypt ? crypto_random(16) : data[1:16])
    try
        cctx = CipherContext("aes_256_cbc", key, iv, isencrypt)
        d = isencrypt ? update!(cctx, data) : update!(cctx, (@view data[17:end]))
        append!(d, close(cctx))
        return d
    finally
        shred!(key); shred!(iv)
    end
end

function crypt(h::SecHandler, params::CryptParams,
               data::Vector{UInt8}, isencrypt::Bool)
    cfm = get_cfm(h, params.cfn)
    cfm === cn"None"  && return data
    cfm === cn"AESV3" && return algo01a(h, params, data, isencrypt)
    return algo01(h, params, data, isencrypt)
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
    if filters isa CosNullType ||
        (filters isa CosName && cn"Crypt" === filters) ||
        (filters isa CosArray &&
         (length(filters) == 0 ||
          (length(filters) == 1 && cn"Crypt" === filters[1])))
        set!(o, cn"FFilter", CosNull)
        set!(o, cn"FDecodeParms", CosNull)
    elseif filters isa CosArray && cn"Crypt" === filters[1]
        deleteat!(get(filters), 1)
        params = get(o, cn"FDecodeParms")
        params !== CosNull && deleteat!(get(params), 1)
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
