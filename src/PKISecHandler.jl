using Base: prompt, getpass, SecretBuffer, SecretBuffer!, shred!
using ..Common

mutable struct PKISecHandler <: SecHandler
    subtype::CosName
    version::Tuple{Int, Int}
    length::Int
    r::Int
    o::Vector{UInt8}
    u::Vector{UInt8}
    oe::Vector{UInt8}
    ue::Vector{UInt8}
    p::UInt32 
    perms::Vector{UInt8}
    id::Vector{UInt8}
    cf::Union{CosDict, CosNullType}
    stmf::CosName
    strf::CosName
    eff::CosName
    access::Function
    skey_path::String
    iv_path::String
    keys::Dict{CosName, Tuple{UInt32, Vector{UInt8}}}
end

function PKISecHandler(doc::CosDoc, subtype::CosName, access::Function)
    enc = doc.encrypt
    length = get(get(enc, cn"Length", CosInt(128)))
    vrsn   = doc.version
    subtype in [cn"adbe.pkcs7.s3", cn"adbe.pkcs7.s4", cn"adbe.pkcs7.s5"] ||
        error("Unsupported release of security handler")

    r = subtype === cn"adbe.pkcs7.s3" ? 2 :
        subtype === cn"adbe.pkcs7.s4" ? 3 : 4
    o      = Vector{UInt8}(get(enc, cn"O")) 
    u      = Vector{UInt8}(get(enc, cn"U"))
    oe     = Vector{UInt8}(get(enc, cn"OE"))
    ue     = Vector{UInt8}(get(enc, cn"UE"))
    p      = reinterpret(UInt32, Int32(get(get(enc, cn"P", CosInt(0)))))
    perms  = Vector{UInt8}(get(enc, cn"Perms"))
    ids = cosDocGetID(doc)
    id = Vector{UInt8}(ids[1])

    cf   = get(enc, cn"CF", CosDict())
    if r < 4
        d = CosDict()
        set!(cf, cn"DefaultCryptFilter", d)
        set!(d, cn"Type", cn"CryptFilter")
        set!(d, cn"CFM", cn"V2")
        set!(d, cn"AuthEvent", cn"DocOpen")
        set!(d, cn"Recipients", get(enc, cn"Recipients"))
        set!(d, cn"EncryptMetadata", get(enc, cn"EncryptMetadata", CosTrue))
        set!(d, cn"Length", get(enc, cn"Length", CosInt(128)))
        stmf = get(enc, cn"StmF", cn"DefaultCryptFilter")
        strf = get(enc, cn"StrF", cn"DefaultCryptFilter")
    else
        stmf = get(enc, cn"StmF", cn"Identity")
        strf = get(enc, cn"StrF", cn"Identity")
    end
    eff  = get(enc, cn"EFF", stmf)
    eff !== stmf &&
        Base.@warn("Embedded file streams without Crypt filters may not decrypt")
    access === identity && (access = get_digital_id)
    skey_path, io = get_tempfilepath()
    # Ensure the files have enough bytes in them.
    shred!(SecretBuffer!(crypto_random(rand(1000:10000)))) do s
        write(io, s)
        close(io)
    end
    iv_path, io = get_tempfilepath()
    # Ensure the files have enough bytes in them.
    shred!(SecretBuffer!(crypto_random(rand(1000:10000)))) do s
        write(io, s)
        close(io)
    end
    keys = Dict(cn"Identity" => (0xffffffff, Vector{UInt8}()))
    return PKISecHandler(subtype, vrsn, length, r, o, u, oe, ue,
                         p, perms, id, cf, stmf, strf, eff, access,
                         skey_path, iv_path, keys)
end

function get_digital_id()
    p12file = ""
    while !isfile(p12file)
        p12file =
            prompt("Select the PCKS#12 (.p12) certificate for the recepient")
    end
    p12pass = getpass("Enter the password to open the PKCS#12 (.p12) file")
    return shred!(x->read_pkcs12(p12file, x), p12pass)
end

function get_key(h::PKISecHandler, cfn::CosName, access::Function)
    cert, pkey = access()
    cf = get(h.cf, cfn)
    rs = get(cf, cn"Recipients")
    data = nothing
    flags = Cint(CMS_BINARY)
    digbuf, rbuf, perm = nothing, IOBuffer(), UInt32(0)
    try
        for r in get(rs)
            rb = Vector{UInt8}(r)
            write(rbuf, rb)
            data !== nothing && continue
            ci = CMSContentInfo(rb)
            data = decrypt(ci, pkey, cert, Vector{UInt8}(undef, 0), flags)
            if data !== nothing
                if length(data) > 20 
                    bperm = data[21:24]
                    ENDIAN_BOM == 0x04030201 && reverse!(bperm)
                    perm = reinterpret(UInt32, bperm)[1]
                end
                digbuf = SecretBuffer!(data)
                digbuf.size = 20
                seekend(digbuf)
            end
        end
        data === nothing &&
            error("Unable to decrypt with recepient certificate")
        write(digbuf, take!(rbuf))
        encMetadata = get(get(cf, cn"EncryptMetadata", CosTrue))
        !encMetadata && write(digbuf, fill(0xff, 4))
        cfm = get_cfm(h, cfn)
        algo = cfm === cn"AESV3" ? "sha256" : "sha1"
        mdctx = DigestContext(algo)
        update!(mdctx, (@view digbuf.data[1:digbuf.size]))
        key = SecretBuffer!(close(mdctx))
        h.length = get(get(cf, cn"Length"))
        key.size = h.length / 8
        return store_key(h, cfn, (perm, key))
    finally
        digbuf !== nothing && shred!(digbuf)
    end
end
