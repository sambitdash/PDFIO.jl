using Base: Unicode, SecretBuffer, SecretBuffer!, getpass, shred!

const PASSWD_PADDING =
    [0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41,
     0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08,
     0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80,
     0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A]

const AES_SUFFIX = [0x73, 0x41, 0x6C, 0x54] # sAlT

function UTF8ToPDFEncoding(s::SecretBuffer)
    r = SecretBuffer()
    while !eof(s)
        write(r, UnicodeToPDFEncoding(read(s, Char)))
    end
    return seekstart(r)
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
    password::Function
    keys::Dict{CosName, Tuple{UInt32, Vector{UInt8}}}
end

const STORE_KEY = crypto_random(32)
const STORE_IV  = crypto_random(16)

function store_key(s::StdSecHandler, cfn::CosName,
                   data::Tuple{UInt32, SecretBuffer})

    skey = SecretBuffer(); iv = SecretBuffer()
    write(skey, STORE_KEY); write(iv, STORE_IV)
    cctx = CipherContext("aes_256_cbc", skey, iv, true)
    shred!(skey); shred!(iv)

    perm, key = data
    c = update!(cctx, key)
    append!(c, close(cctx))
    s.keys[cfn] = (perm, c)
    return data
end

function get_key(s::StdSecHandler, cfn::CosName)
    permkey = get(s.keys, cfn, nothing)
    permkey === nothing && return nothing
    
    skey = SecretBuffer(); iv = SecretBuffer()
    write(skey, STORE_KEY); write(iv, STORE_IV)
    cctx = CipherContext("aes_256_cbc", skey, iv, false)
    shred!(skey); shred!(iv)
    
    perm, c = permkey
    b = update!(cctx, c)
    append!(b, close(cctx))
    return perm, SecretBuffer!(b)
end

CryptParams(h::StdSecHandler, oi::CosIndirectObject) = 
    CryptParams(h, oi.num, oi.gen, oi.obj)

CryptParams(h::StdSecHandler, num::Int, gen::Int, o::CosObject) =
    h.r < 4 ? CryptParams(num, gen, cn"StdCF") : error(E_INVALID_OBJECT)

CryptParams(h::StdSecHandler, num::Int, gen::Int, o::CosString) =
    CryptParams(num, gen, h.strf)

CryptParams(h::StdSecHandler, num::Int, gen::Int, o::CosObjectStream) =
    CryptParams(h, num, gen, o.stm)

function CryptParams(h::StdSecHandler, num::Int, gen::Int, o::CosStream)
    cfn = nothing
    filters = get(o, cn"FFilter")
    if filters isa CosName
        if cn"Crypt" === filters
            params = get(o, cn"FDecodeParms")
            cfn = get(params, cn"Name")
        end
    elseif filters isa CosArray
        i = findnext(x -> x === cn"Crypt", get(filters), 1)
        params = get(o, cn"FDecodeParms")
        cfn = get(params[i], cn"Name")
        # i > 1 && decode_until(
    end
    return CryptParams(num, gen, cfn !== nothing ? cfn : h.stmf)
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

function algo01(h::StdSecHandler, params::CryptParams,
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
    n != key.size && error("Invalid encryption key length")
    md = shred!(key) do kc
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
    cctx = CipherContext(isRC4 ? "rc4" : "aes_128_cbc", key, iv, isencrypt)
    shred!(key); shred!(iv)
    d = (isRC4 || isencrypt) ? update!(cctx, data) :
                               update!(cctx, (@view data[17:end]))
    append!(d, close(cctx))
    return d
end

function algo01a(h::StdSecHandler, params::CryptParams,
                data::AbstractVector{UInt8}, isencrypt::Bool)
    perm, key = get_key(h, params)
    iv = SecretBuffer!(isencrypt ? crypto_random(16) : data[1:16]) 
    cctx = CipherContext("aes_256_cbc", key, iv, isencrypt)
    shred!(key); shred!(iv)
    d = isencrypt ? update!(cctx, data) : update!(cctx, (@view data[17:end]))
    append!(d, close(cctx))
    return d
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
    cctx = CipherContext("aes_256_cbc", ik, iv, false)
    shred!(ik); shred!(iv)
    set_padding(cctx, 0)
    de = isowner ? oe : ue
    fek = SecretBuffer!(update!(cctx, de))
    write(seekend(fek), close(cctx))
    # f
    return algo13(h, seekstart(fek)) ? seekstart(fek) : nothing
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
    mdctx = DigestContext("md5")
    update!(mdctx, PASSWD_PADDING)
    update!(mdctx, h.id)
    md = close(mdctx)

    iv = SecretBuffer!(UInt8[])

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
    shred!(iv)
    return c, key
end

algo05(h::StdSecHandler, password::Vector{UInt8}) = error(E_NOT_IMPLEMENTED)

function algo06(h::StdSecHandler, password::SecretBuffer)
    (u, key) = h.r == 2 ? algo04(h, password) : algo05p_a_e(h, password) 
    return u == h.u[1:16] ? key : nothing
end

function algo07(h::StdSecHandler, password::SecretBuffer)
    # a
    key = SecretBuffer!(algo03p_a_d(h, password))
    # b
    iv = SecretBuffer!(UInt8[])
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
    shred!(iv); shred!(key)
    return shred!(upw -> algo06(h, upw), SecretBuffer!(od))
end

algo08(h::StdSecHandler, password::Vector{UInt8}) = error(E_NOT_IMPLEMENTED)
algo09(h::StdSecHandler, password::Vector{UInt8}) = error(E_NOT_IMPLEMENTED)
algo10(h::StdSecHandler, password::Vector{UInt8}) = error(E_NOT_IMPLEMENTED)

function algo11(h::StdSecHandler, password::SecretBuffer)
    println("")
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

function SecHandler(doc::CosDoc, access::Union{String, Function})
    enc = doc.encrypt
    get(enc, cn"Filter") === cn"Standard" || return nothing
    v      = get(get(enc, cn"V", CosInt(0)))
    v >= 1 || return nothing
    return StdSecHandler(doc, v, access)
end

function StdSecHandler(doc::CosDoc, v::Int, access::Union{String, Function})
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
    access === identity && (access = doUI)
    keys = Dict(cn"Identity" => (0xffffffff, Vector{UInt8}()))
    return StdSecHandler(v, vrsn, length, r, o, u, oe, ue,
                         p, perms, encMetadata, id,
                         cf, stmf, strf, eff, access, keys)
end

function crypt(h::SecHandler, params::CryptParams,
               data::Vector{UInt8}, isencrypt::Bool)
    cfm = get_cfm(h, params.cfn)
    cfm === cn"None"  && return data
    cfm === cn"AESV3" && return algo01a(h, params, data, isencrypt)
    return algo01(h, params, data, isencrypt)
end

function get_cfm(h::StdSecHandler, cfn::CosName)
    cfn === cn"Identity" && return cn"None"
    cfm = get(get(h.cf, cfn), cn"CFM")
    cfm in [cn"None", cn"V2", cn"AESV2", cn"AESV3"] || error(E_INVALID_CRYPT)
    return cfm
end

function validateUserPW(h::StdSecHandler, cfn::CosName, password::SecretBuffer)
    cfm = get_cfm(h, cfn)
    cfm === cn"None"  && return Vector{UInt8}()
    cfm === cn"V2"    && return algo06(h, password)
    cfm === cn"AESV2" && return algo06(h, password)
    cfm === cn"AESV3" && return algo11(h, password)
    error(E_INVALID_CRYPT)
end

function validateOwnerPW(h::StdSecHandler, cfn::CosName, password::SecretBuffer)
    cfm = get_cfm(h, cfn)
    cfm === cn"None"  && return Vector{UInt8}()
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

funicode(h::StdSecHandler, cfn::CosName, pw::SecretBuffer) =
    shred!(UTF8ToPDFEncoding, pw)

function get_key(h::StdSecHandler, params::CryptParams)
    vpw = get_key(h, params.cfn)
    vpw === nothing || return vpw
    return get_key(h, params.cfn, h.password)
end

function get_key(h::StdSecHandler, cfn::CosName, password::Function)
    vpw = shred!(pw -> validatePW(h, cfn, pw), SecretBuffer(""))
    vpw === nothing || return store_key(h, cfn, vpw)
    i = 1
    while vpw === nothing && i <= 3
        vpw = shred!(pw -> validatePW(h, cfn, pw), funicode(h, cfn, password()))
        i += 1
    end
    vpw === nothing && error(E_INVALID_PASSWORD)
    return store_key(h, cfn, vpw)
end
