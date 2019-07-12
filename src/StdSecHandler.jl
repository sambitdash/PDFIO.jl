using Base: Unicode, SecretBuffer, SecretBuffer!, getpass, shred!

const PASSWD_PADDING =
    [0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41,
     0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08,
     0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80,
     0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A]

const AES_SUFFIX = [0x73, 0x41, 0x6C, 0x54] # sAlT

function UTF8ToPDFEncoding!(s::SecretBuffer)
    try
        r = SecretBuffer()
        while !eof(s)
            write(r, UnicodeToPDFEncoding(read(s, Char)))
        end
        return seekstart(r)
    finally
        shred!(s)
    end
end

struct StdSecHandler <: SecHandler
    v::Int
    version::Tuple{Int, Int}
    length::Int
    r::Int
    o::Vector{UInt8}
    u::Vector{UInt8}
    oe::Vector{UInt8}
    ue::Vector{UInt8}
    p::UInt32 
    perms::Vector{UInt8}
    encMetadata::Bool
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

# Output 32-bytes padded password
function get_padded_pw(password::SecretBuffer)
    up, l = SecretBuffer(), password.size
    if l < 32
        write(up, password)
        write(up, PASSWD_PADDING[1:32-l])
    else
        for i = 1:32
            write(up, password.data[i])
        end
    end
    return seekstart(up)
end

function algo02(h::StdSecHandler, password::SecretBuffer)
    # step a, b
    mdctx = DigestContext("md5")
    shred!(get_padded_pw(password)) do pw
        update!(mdctx, pw)
    end
    # c
    update!(mdctx, h.o)
    # d
    p = copy(reinterpret(UInt8, [h.p]))
    ENDIAN_BOM == 0x01020304 && reverse!(p)
    update!(mdctx, p)
    # e, ID
    update!(mdctx, h.id)
    # f
    h.r >= 4 && !h.encMetadata && update!(mdctx, fill(0xff, 4))
    # g
    md = close(mdctx)
    # h
    n = 5
    if h.r >= 3
        n = div(h.length, 8)
        for i = 1:50
            reset(mdctx)
            init(mdctx)
            md = md[1:n]
            update!(mdctx, md)
            md = close(mdctx)
        end
    end
    md = md[1:n]
    return md
end

function algo02a(h::StdSecHandler, pw::SecretBuffer, isowner::Bool)
    # b
    seekstart(pw)
    pw.size > 127 && (pw.size = 127)

    o, u, oe, ue = h.o, h.u, h.oe, h.ue
    ov, ovs, oks = (@view o[1:32]), (@view o[33:40]), (@view o[41:48])
    uv, uvs, uks = (@view u[1:32]), (@view u[33:40]), (@view u[41:48])
    # c
    if isowner
        or = shred!(SecretBuffer()) do pv
            write(pv, pw); write(pv, ovs); write(pv, u)
            return algo02b(h, pw, seekstart(pv), true)
        end
        or != ov && return nothing
    end
    # d, e
    ik = shred!(SecretBuffer()) do pv
        if isowner
            write(pv, pw); write(pv, oks); write(pv, u)
        else
            write(pv, pw); write(pv, uks)
        end
        return SecretBuffer!(algo02b(h, pw, seekstart(pv), isowner))
    end
    iv = SecretBuffer!(fill(0x00, 16))
    try
        cctx = CipherContext("aes_256_cbc", ik, iv, false)
        set_padding(cctx, 0)
        de = isowner ? oe : ue
        fek = SecretBuffer!(update!(cctx, de))
        write(seekend(fek), close(cctx))
        # f
        return algo13(h, seekstart(fek)) ? seekstart(fek) : nothing
    finally
        shred!(ik); shred!(iv)
    end
end

function algo02b(h::StdSecHandler, password::SecretBuffer,
                 input::SecretBuffer, isOwner::Bool)
    dgst_algo = "sha256"
    mdctx = DigestContext(dgst_algo)
    update!(mdctx, input)
    k = close(mdctx)
    if h.r > 5
        round = 0
        for i = 1:100 # The spec says by 80 most cases should converge
            # a
            e = shred!(SecretBuffer()) do k1
                write(k1, password); write(k1, k); (isOwner && write(k1, h.u))
                for i = 1:6 # 2^6 = 64
                    write(k1, k1)
                end
                # b
                key = SecretBuffer!(k[1:16]); iv = SecretBuffer!(k[17:32])
                cctx = CipherContext("aes_128_cbc", key, iv, true)
                shred!(key); shred!(iv)
                set_padding(cctx, 0)
                e = update!(cctx, k1)
                append!(e, close(cctx))
                return e
            end
            # c
            bn = BigNum(e[1:16])
            m = mod(bn, UInt(3))
            dgst_algo = m == 0 ? "sha256" : m == 1 ? "sha384" : "sha512"
            # d
            mdctx = DigestContext(dgst_algo)
            update!(mdctx, e)
            k = close(mdctx)
            i <= 64 && continue
            # e
            e[end] > (i - 33) && continue
            # f
            round = i - 1
            break
        end
        round == 0 && error("Unable to hash the password")
    end
    return k[1:32]
end

function algo03p_a_d(h::StdSecHandler, password::SecretBuffer)
    # a, b
    mdctx = DigestContext("md5")
    shred!(get_padded_pw(password)) do pw
        update!(mdctx, pw)
    end
    md = close(mdctx)
    # c
    if h.r >= 3
        for i = 1:50
            reset(mdctx); init(mdctx)
            update!(mdctx, md)
            md = close(mdctx)
        end
    end
    # d
    n = h.r == 2 ? 5 : div(h.length, 8)
    return md[1:n]
end

algo03(h::StdSecHandler, password::Vector{UInt8}) = error(E_NOT_IMPLEMENTED)

function algo04(h::StdSecHandler, password::SecretBuffer)
    key = SecretBuffer!(algo02(h, password))
    iv = SecretBuffer!(UInt8[])
    cctx = CipherContext("rc4", key, iv, true)
    shred!(iv)
    u = update!(cctx, PASSWD_PADDING)
    c = close(cctx)
    reset(cctx)
    return append!(u, c), key
end

function modkey(key::SecretBuffer, f::Int)
    mk = SecretBuffer()
    for i = 1:key.size
        write(mk, xor(key.data[i], UInt8(f)))
    end
    return mk
end

function algo05p_a_e(h::StdSecHandler, password::SecretBuffer)
    key = SecretBuffer!(algo02(h, password))
    iv = SecretBuffer!(UInt8[])
    try
        mdctx = DigestContext("md5")
        update!(mdctx, PASSWD_PADDING)
        update!(mdctx, h.id)
        md = close(mdctx)
        cctx = CipherContext("rc4", key, iv, true)
        c = update!(cctx, md)
        append!(c, close(cctx))

        for i = 1:19
            reset(cctx)
            shred!(modkey(key, i)) do tkey
                init(cctx, tkey, iv, true)
            end
            c = update!(cctx, c)
            append!(c, close(cctx))
        end
        return c, key
    finally
        shred!(iv)
    end
end

algo05(h::StdSecHandler, password::Vector{UInt8}) = error(E_NOT_IMPLEMENTED)

function algo06(h::StdSecHandler, password::SecretBuffer)
    (u, key) = h.r == 2 ? algo04(h, password) : algo05p_a_e(h, password) 
    u == h.u[1:16] && return key
    shred!(key)
    return nothing
end

function algo07(h::StdSecHandler, password::SecretBuffer)
    # a
    key = SecretBuffer!(algo03p_a_d(h, password))
    # b
    iv = SecretBuffer!(UInt8[])
    try
        cctx = CipherContext("rc4", key, iv, false)
        od, count = h.o, (h.r == 2 ? 0 : 19)
        for i = count:-1:0
            reset(cctx)
            shred!(modkey(key, i)) do tkey
                init(cctx, tkey, iv, false)
            end
            od = update!(cctx, od)
            append!(od, close(cctx))
        end
        return shred!(upw -> algo06(h, upw), SecretBuffer!(od))
    finally
        shred!(iv); shred!(key)
    end
end

algo08(h::StdSecHandler, password::Vector{UInt8}) = error(E_NOT_IMPLEMENTED)
algo09(h::StdSecHandler, password::Vector{UInt8}) = error(E_NOT_IMPLEMENTED)
algo10(h::StdSecHandler, password::Vector{UInt8}) = error(E_NOT_IMPLEMENTED)

function algo11(h::StdSecHandler, password::SecretBuffer)
    u = h.u
    uv, uvs, uks = (@view u[1:32]), (@view u[33:40]), (@view u[41:48])
    uc = shred!(SecretBuffer()) do upw
        write(upw, password); write(upw, uvs)
        return algo02b(h, password, seekstart(upw), false)
    end
    return uc == u[1:32] ? algo02a(h, password, false) : nothing
end

function algo12(h::StdSecHandler, password::SecretBuffer)
    o = h.o
    ov, ovs, oks = (@view o[1:32]), (@view o[33:40]), (@view o[41:48])
    oc = shred!(SecretBuffer()) do opw
        write(opw, password); write(opw, ovs); write(opw, h.u)
        return algo02b(h, password, seekstart(opw), true)
    end
    return oc == o[1:32] ? algo02a(h, password, true) : nothing
end

function algo13(h::StdSecHandler, fek::SecretBuffer)
    perms = h.perms
    cctx = shred!(SecretBuffer!(fill(0x00, 16))) do iv
        CipherContext("aes_256_ecb", fek, iv, false)
    end
    set_padding(cctx, 0)
    dperm = update!(cctx, perms)
    append!(dperm, close(cctx))
    dperm[10:12] != b"adb" && return false
    dpermp = dperm[1:4]
    ENDIAN_BOM == 0x01020304 && reverse!(dpermp)
    return (h.p == reinterpret(UInt32, dpermp)[1]) 
end

function SecHandler(doc::CosDoc, access::Function)
    enc = doc.encrypt
    if get(enc, cn"Filter") === cn"Standard"
        v      = get(get(enc, cn"V", CosInt(0)))
        v >= 1 || return nothing
        return StdSecHandler(doc, v, access)
    end
    subfilter = get(enc, cn"SubFilter")
    subfilter in [cn"adbe.pkcs7.s3", cn"adbe.pkcs7.s4", cn"adbe.pkcs7.s5"] &&
        return PKISecHandler(doc, subfilter, access)
    error("Incompatible security handler used in the document")
end

function StdSecHandler(doc::CosDoc, v::Int, access::Function)
    enc = doc.encrypt
    length = get(get(enc, cn"Length", CosInt(40)))
    r      = get(get(enc, cn"R"))
    vrsn   = doc.version
    r == 1 && error("Unsupported release of security handler")
    o      = Vector{UInt8}(get(enc, cn"O")) 
    u      = Vector{UInt8}(get(enc, cn"U"))
    oe     = Vector{UInt8}(get(enc, cn"OE"))
    ue     = Vector{UInt8}(get(enc, cn"UE"))
    p      = reinterpret(UInt32, Int32(get(get(enc, cn"P"))))
    perms  = Vector{UInt8}(get(enc, cn"Perms"))
    encMetadata = get(get(enc, cn"EncryptMetadata", CosTrue))
    ids = cosDocGetID(doc)
    id = Vector{UInt8}(ids[1])

    cf   = get(enc, cn"CF", CosDict())
    if r < 4
        d = CosDict()
        set!(cf, cn"StdCF", d)
        set!(d, cn"Type", cn"CryptFilter")
        set!(d, cn"CFM", cn"V2")
        set!(d, cn"AuthEvent", cn"DocOpen")
        stmf = get(enc, cn"StmF", cn"StdCF")
        strf = get(enc, cn"StrF", cn"StdCF")
    else
        stmf = get(enc, cn"StmF", cn"Identity")
        strf = get(enc, cn"StrF", cn"Identity")
    end
    eff  = get(enc, cn"EFF", stmf)
    eff !== stmf &&
        Base.@warn("Embedded file streams without Crypt filters may not decrypt")
    access === identity && (access = doUI)
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
    return StdSecHandler(v, vrsn, length, r, o, u, oe, ue,
                         p, perms, encMetadata, id,
                         cf, stmf, strf, eff, access,
                         skey_path, iv_path, keys)
end

function validateUserPW(h::StdSecHandler, cfn::CosName, password::SecretBuffer)
    cfm = get_cfm(h, cfn)
    cfm === cn"None"  && return SecretBuffer!(Vector{UInt8}(undef, 0))
    cfm === cn"V2"    && return algo06(h, password)
    cfm === cn"AESV2" && return algo06(h, password)
    cfm === cn"AESV3" && return algo11(h, password)
    error(E_INVALID_CRYPT)
end

function validateOwnerPW(h::StdSecHandler, cfn::CosName, password::SecretBuffer)
    cfm = get_cfm(h, cfn)
    cfm === cn"None"  && return SecretBuffer!(Vector{UInt8}(undef, 0))
    cfm === cn"V2"    && return algo07(h, password)
    cfm === cn"AESV2" && return algo07(h, password)
    cfm === cn"AESV3" && return algo12(h, password)
    error(E_INVALID_CRYPT)
end

doUI() = Base.getpass("Enter the password to open the document")

function validatePW(h::StdSecHandler, cfn::CosName, s::SecretBuffer)
    key = validateOwnerPW(h, cfn, seekstart(s))
    key !== nothing && return 0xffffffff, key
    key = validateUserPW(h, cfn, seekstart(s))
    key !== nothing && return h.p, key
    return nothing
end

funicode!(h::StdSecHandler, cfn::CosName, pw::SecretBuffer) =
    shred!(UTF8ToPDFEncoding!, pw)

function get_key(h::StdSecHandler, cfn::CosName, password::Function)
    vpw = shred!(pw -> validatePW(h, cfn, pw), SecretBuffer(""))
    vpw === nothing || return store_key(h, cfn, vpw)
    i = 1
    while vpw === nothing && i <= 3
        vpw = shred!(pw -> validatePW(h, cfn, pw), funicode!(h, cfn, password()))
        i += 1
    end
    vpw === nothing && error(E_INVALID_PASSWORD)
    return store_key(h, cfn, vpw)
end
