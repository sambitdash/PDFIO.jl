@static isfile(joinpath(dirname(@__FILE__), "..", "deps", "deps.jl")) ||
        error("PDFIO not properly installed. Please run Pkg.build(\"PDFIO\")")

include("../deps/deps.jl")

using Dates

const V_ASN1_UNDEF                    = Cint(-1)
const V_ASN1_EOC                      = Cint(0)
const V_ASN1_BOOLEAN                  = Cint(1)
const V_ASN1_INTEGER                  = Cint(2)
const V_ASN1_BIT_STRING               = Cint(3)
const V_ASN1_OCTET_STRING             = Cint(4)
const V_ASN1_NULL                     = Cint(5)
const V_ASN1_OBJECT                   = Cint(6)
const V_ASN1_OBJECT_DESCRIPTOR        = Cint(7)
const V_ASN1_EXTERNAL                 = Cint(8)
const V_ASN1_REAL                     = Cint(9)
const V_ASN1_ENUMERATED               = Cint(10)
const V_ASN1_UTF8STRING               = Cint(12)
const V_ASN1_SEQUENCE                 = Cint(16)
const V_ASN1_SET                      = Cint(17)
const V_ASN1_NUMERICSTRING            = Cint(18)
const V_ASN1_PRINTABLESTRING          = Cint(19)
const V_ASN1_T61STRING                = Cint(20)
const V_ASN1_TELETEXSTRING            = Cint(20)
const V_ASN1_VIDEOTEXSTRING           = Cint(21)
const V_ASN1_IA5STRING                = Cint(22)
const V_ASN1_UTCTIME                  = Cint(23)
const V_ASN1_GENERALIZEDTIME          = Cint(24)
const V_ASN1_GRAPHICSTRING            = Cint(25)
const V_ASN1_ISO64STRING              = Cint(26)
const V_ASN1_VISIBLESTRING            = Cint(26)
const V_ASN1_GENERALSTRING            = Cint(27)
const V_ASN1_UNIVERSALSTRING          = Cint(28)
const V_ASN1_BMPSTRING                = Cint(30)


# Abstraction around OpenSSL libcrypto methods

# Memory BIO from OpenSSL BIO interface as a Julia IO
mutable struct BIO <: IO
    data::Ptr{Cvoid}
    function BIO(bio::Ptr{Cvoid})
        this = new(bio)
        finalizer(x->ccall((:BIO_vfree, libcrypto), Cvoid,
                           (Ptr{Cvoid}, ), x.data), this)
    end
end

# Readonly memory BIO
function BIO(membuf::Vector{UInt8})
    bio = ccall((:BIO_new_mem_buf, libcrypto), Ptr{Cvoid},
                (Ptr{Cvoid}, Cint), pointer(membuf), length(membuf))
    bio == C_NULL && openssl_error(0)
    return BIO(bio)
end

# R/W Memory BIO
function BIO()
    buf_bio = ccall((:BIO_s_mem, libcrypto), Ptr{Cvoid}, ())
    buf_bio == C_NULL && openssl_error(0)
    bio = ccall((:BIO_new, libcrypto), Ptr{Cvoid}, (Ptr{Cvoid}, ), buf_bio)
    bio == C_NULL && openssl_error(0)
    return BIO(bio)    
end

function Base.read(bio::BIO)
    n, size = Csize_t(4096), Csize_t(4096)
    out, buf = Vector{UInt8}(undef, 0), Vector{UInt8}(undef, size)
    while n >= size
        n = ccall((:BIO_read, libcrypto), Cint,
                  (Ptr{Cvoid}, Ptr{Cvoid}, Csize_t),
                  bio.data, pointer(buf), size)
        n > 0 && append!(out, @view buf[1:n])
    end
    return out
end

function get_date_from_utctime(d::String)
    # Remove fraction seconds if there
    @assert d[end] == 'Z'
    a = split(d, '.')
    length(a) > 1 && (d = a[1]*"Z")
    pfx = length(d) == 15 ? "D:" :
          parse(Int, d[1:2]) < 50 ? "D:20" : "D:19"
    return CDDate(pfx*d)
end

read_cddate(bio::BIO) =
    bio |> read |> pointer |> unsafe_string |> get_date_from_utctime

function openssl_error(ret)
    ret <= 0 || return nothing
    errmsg = "Error in Crypto Library: "
    bio = BIO()
    ccall((:ERR_print_errors, libcrypto), Cvoid, (Ptr{Cvoid}, ), bio.data)
    data = read(bio)
    msg = transcode(String, data)
    error(errmsg*"\n\n"*msg)
end

const EVP_MAX_MD_SIZE = Cint(64)

function get_message_digest(doc::PDDoc, brange::Vector{Int}, algo::String)
    mdctx = ccall((:EVP_MD_CTX_new, libcrypto), Ptr{Cvoid}, ())
    mdctx == C_NULL && error("Unable to create digest context")
    try 
        md = ccall((:EVP_get_digestbyname, libcrypto), Ptr{Cvoid},
               (Ptr{Cstring}, ), pointer(algo))
        md == C_NULL && error("Unable to find message digest algorithm "*algo)
        ret = ccall((:EVP_DigestInit_ex, libcrypto), Cint,
                    (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}), mdctx, md, C_NULL)
        openssl_error(ret)
        for i = 1:2:length(brange)
            buff = readfrom(doc.cosDoc, brange[i], brange[i+1])
            ret = ccall((:EVP_DigestUpdate, libcrypto), Cint,
                        (Ptr{Cvoid}, Ptr{Cuchar}, Cint),
                        mdctx, pointer(buff), brange[i+1])
            openssl_error(ret)
        end
        md_value = Vector{UInt8}(undef, EVP_MAX_MD_SIZE)
        md_len = Ref(EVP_MAX_MD_SIZE)
        ret = ccall((:EVP_DigestFinal_ex, libcrypto), Cint,
                    (Ptr{Cvoid}, Ptr{Cuchar}, Ptr{Cint}),
                    mdctx, md_value, md_len)
        openssl_error(ret)
        resize!(md_value, md_len[])
        return md_value
    finally
        ccall((:EVP_MD_CTX_free,  libcrypto), Cvoid, (Ptr{Cvoid}, ), mdctx)
    end
end

mutable struct PDCertStore
    data::Ptr{Cvoid}
    function PDCertStore()
        store   = ccall((:X509_STORE_new,   libcrypto), Ptr{Cvoid}, ())
        this = new(store)
        finalizer(x->ccall((:X509_STORE_free, libcrypto),
                           Cvoid, (Ptr{Cvoid}, ), x.data), this)

        flookup = ccall((:X509_LOOKUP_file, libcrypto), Ptr{Cvoid}, ())
        lookup  = ccall((:X509_STORE_add_lookup, libcrypto), Ptr{Cvoid},
                        (Ptr{Cvoid}, Ptr{Cvoid}), store, flookup)
    
        cacerts   = joinpath(@__DIR__, "..", "data", "certs", "cacerts.pem")
        adoberoot = joinpath(@__DIR__, "..", "data", "certs", "adoberoot.pem")
        # Ensure a cacerts.pem file is always there.
        isfile(cacerts) || cp(adoberoot, cacerts)
        
        ret = ccall((:X509_STORE_load_locations, libcrypto), Cint,
                    (Ptr{Cvoid}, Ptr{Cstring}, Ptr{Cstring}),
                    store, transcode(UInt8, cacerts), C_NULL)
        openssl_error(ret)

        ccall((:X509_STORE_set_default_paths, libcrypto),
              Cvoid, (Ptr{Cvoid}, ), store)
        return this
    end    
end

const X509_PURPOSE_SSL_CLIENT         = Cint(1)
const X509_PURPOSE_SSL_SERVER         = Cint(2)
const X509_PURPOSE_NS_SSL_SERVER      = Cint(3)
const X509_PURPOSE_SMIME_SIGN         = Cint(4)
const X509_PURPOSE_SMIME_ENCRYPT      = Cint(5)
const X509_PURPOSE_CRL_SIGN           = Cint(6)
const X509_PURPOSE_ANY                = Cint(7)
const X509_PURPOSE_OCSP_HELPER        = Cint(8)
const X509_PURPOSE_TIMESTAMP_SIGN     = Cint(9)

function set_params(store::PDCertStore, d::Dict)
    param = ccall((:X509_VERIFY_PARAM_new, libcrypto), Ptr{Cvoid}, ())
    depth   = get(d, :depth, 16)
    ccall((:X509_VERIFY_PARAM_set_depth, libcrypto), Cvoid,
          (Ptr{Cvoid}, Cint), param, depth)
    purpose = get(d, :purpose, X509_PURPOSE_ANY)
        ccall((:X509_VERIFY_PARAM_set_purpose, libcrypto), Cvoid,
              (Ptr{Cvoid}, Cint), param, purpose)
    atepoch = get(d, :atepoch, nothing)
    atepoch !== nothing && 
        ccall((:X509_VERIFY_PARAM_set_time, libcrypto), Cvoid,
              (Ptr{Cvoid}, Cint), param, atepoch)
    ccall((:X509_STORE_set1_param, libcrypto), Cvoid,
          (Ptr{Cvoid}, Ptr{Cvoid}), store.data, param)
    ccall((:X509_VERIFY_PARAM_free, libcrypto), Cvoid, (Ptr{Cvoid}, ), param)
    return nothing
end

abstract type SignedInfo end

struct PKCS1SignedInfo <: SignedInfo
    doc::PDDoc
    brange::Vector{Int}
    sdata::Vector{UInt8}
    function PKCS1SignedInfo(doc::PDDoc, brange::Vector{Int}, sd::Vector{UInt8})
        str = ccall((:d2i_ASN1_OCTET_STRING, libcrypto), Ptr{Cvoid},
                    (Ptr{Cvoid}, Ptr{Ptr{UInt8}}, Clong),
                    C_NULL, Ref(pointer(sd)), length(sd))
        str == C_NULL && error("Unable to read PKCS#1 SignedInfo data")
        len = ccall((:ASN1_STRING_length, libcrypto), Cint, (Ptr{Cvoid}, ), str)
        p = ccall((:ASN1_STRING_get0_data, libcrypto), Ptr{Cuchar},
                  (Ptr{Cvoid}, ), str)
        sdata = Vector{UInt8}(undef, len)
        unsafe_copyto!(pointer(sdata), p, len)
        new(doc, brange, sdata)
    end
end

mutable struct CMSSignedInfo <: SignedInfo 
    doc::PDDoc
    brange::Vector{Int}
    cms::Ptr{Cvoid}
    detached::Bool
    function CMSSignedInfo(doc::PDDoc,
                           brange::Vector{Int},
                           contents::Vector{UInt8},
                           detached::Bool = false)
        cms = ccall((:d2i_CMS_ContentInfo, libcrypto), Ptr{Cvoid},
                    (Ptr{Cvoid}, Ptr{Ptr{UInt8}}, Clong),
                    C_NULL, Ref(pointer(contents)), length(contents))
        cms == C_NULL && error("Unable to read CMS SignedInfo data")
        this = new(doc, brange, cms, detached)
        finalizer(x->ccall((:CMS_ContentInfo_free, libcrypto),
                           Cvoid, (Ptr{Cvoid}, ), x.cms), this)
        return this
    end
end

function Base.show(io::IO, si::CMSSignedInfo)
    bio = BIO()
    ret = ccall((:CMS_ContentInfo_print_ctx, libcrypto), Cint,
                (Ptr{Cvoid}, Ptr{Cvoid}, Cint, Ptr{Cvoid}),
                bio.data, si.cms, 2, C_NULL)
    openssl_error(ret)
    return print(io, unsafe_string(pointer(read(bio))))
end

# Can be used only after validation
function get_signer(si::CMSSignedInfo)
    certs = ccall((:CMS_get0_signers, libcrypto), Ptr{Cvoid},
                  (Ptr{Cvoid}, ), si.cms)
    certs == C_NULL && openssl_error(0)
    num = ccall((:OPENSSL_sk_num, libcrypto), Cint, (Ptr{Cvoid}, ), certs)
    num > 1 && error("More than one signer in CMSSignedInfo")
    cert = ccall((:OPENSSL_sk_value, libcrypto), Ptr{Cvoid},
                 (Ptr{Cvoid}, Cint), certs, 0)
    return PDCert(cert, si)
end

mutable struct PDCert
    data::Ptr{Cvoid}
    lockref::Union{CMSSignedInfo, Nothing}
end

# Manage life cycle also. Will be freed along with the Julia object
function PDCert(cert::Ptr{Cvoid})
    this = PDCert(cert, nothing)
    finalizer(x->ccall((:X509_free, libcrypto), Cvoid,
                       (Ptr{Cvoid}, ), x.data), this)
    return this
end

function PDCert(cbytes::Vector{UInt8})
    cdata = ccall((:d2i_X509, libcrypto), Ptr{Cvoid},
                  (Ptr{Cvoid}, Ptr{Ptr{UInt8}}, Clong),
                  C_NULL, Ref(pointer(cbytes)), length(cbytes))
    cdata == C_NULL && error("Invalid certificate data")
    return PDCert(cdata)
end

Base.:(==)(c1::PDCert, c2::PDCert) = !(c1 < c2 || c2 < c1)
Base.isless(c1::PDCert, c2::PDCert) = 
    ccall((:X509_cmp, libcrypto), Cint,
          (Ptr{Cvoid}, Ptr{Cvoid}), c1.data, c2.data) < 0

function is_self_signed(c::PDCert)
    cert = c.data
    ns  = ccall((:X509_get_subject_name, libcrypto), Ptr{Cvoid},
                (Ptr{Cvoid}, ), cert)
    ni  = ccall((:X509_get_issuer_name,  libcrypto), Ptr{Cvoid},
                (Ptr{Cvoid}, ), cert)
    ret = ccall((:X509_NAME_cmp, libcrypto), Cint,
                (Ptr{Cvoid}, Ptr{Cvoid}), ns, ni)
    return ret == 0
end

const X509_LU_X509 = Cint(1)

function find_cert(s::PDCertStore, c::PDCert)
    os = ccall((:X509_STORE_get0_objects, libcrypto),
               Ptr{Cvoid}, (Ptr{Cvoid}, ), s.data)
    ns  = ccall((:X509_get_subject_name, libcrypto), Ptr{Cvoid},
                (Ptr{Cvoid}, ), c.data)
    o  = ccall((:X509_OBJECT_retrieve_by_subject, libcrypto), Ptr{Cvoid},
               (Ptr{Cvoid}, Cint, Ptr{Cvoid}), os, X509_LU_X509, ns)
    o == C_NULL && return false
    c1 = ccall((:X509_OBJECT_get0_X509, libcrypto),
               Ptr{Cvoid}, (Ptr{Cvoid}, ), o)
    c1 == C_NULL && return false
    return PDCert(c1, nothing) == c
end

const ASN1_STRFLGS_ESC_2253           = Culong(1)
const ASN1_STRFLGS_ESC_CTRL           = Culong(2)
const ASN1_STRFLGS_ESC_MSB            = Culong(4)
const ASN1_STRFLGS_ESC_QUOTE          = Culong(8)
const ASN1_STRFLGS_UTF8_CONVERT       = Culong(0x10)
const ASN1_STRFLGS_DUMP_UNKNOWN       = Culong(0x100)
const ASN1_STRFLGS_DUMP_DER           = Culong(0x200)

const ASN1_STRFLGS_RFC2253 =
    ASN1_STRFLGS_ESC_2253 +
    ASN1_STRFLGS_ESC_CTRL +
    ASN1_STRFLGS_ESC_MSB  +
    ASN1_STRFLGS_UTF8_CONVERT +
    ASN1_STRFLGS_DUMP_UNKNOWN +
    ASN1_STRFLGS_DUMP_DER

const XN_FLAG_FN_SN                   = Culong(0)
const XN_FLAG_SEP_CPLUS_SPC           = Culong(2 << 16)
const XN_FLAG_SPC_EQ                  = Culong(1 << 23)

const XN_FLAG_ONELINE =
    ASN1_STRFLGS_ESC_2253 +
    ASN1_STRFLGS_ESC_CTRL +
    ASN1_STRFLGS_ESC_MSB +
    ASN1_STRFLGS_ESC_QUOTE +
    ASN1_STRFLGS_UTF8_CONVERT +
    ASN1_STRFLGS_DUMP_UNKNOWN +
    ASN1_STRFLGS_DUMP_DER +
    XN_FLAG_SEP_CPLUS_SPC +
    XN_FLAG_SPC_EQ + 
    XN_FLAG_FN_SN

const NID_commonName  = Cint(13)
const NID_pkcs9_signingTime = Cint(52)
const NID_id_smime_aa_timeStampToken = Cint(225)
const NID_id_smime_ct_TSTInfo = Cint(207)

const X509_V_OK = Cint(0)

function get_info(c::PDCert)
    info = Dict{Symbol, Any}()
    ns  = ccall((:X509_get_subject_name, libcrypto), Ptr{Cvoid},
                (Ptr{Cvoid}, ), c.data)
    ni  = ccall((:X509_get_issuer_name,  libcrypto), Ptr{Cvoid},
                (Ptr{Cvoid}, ), c.data)
    bio = BIO()
    ret = ccall((:X509_NAME_print_ex, libcrypto), Cint,
                (Ptr{Cvoid}, Ptr{Cvoid}, Cint, Culong),
                bio.data, ns, 0, XN_FLAG_ONELINE)
    openssl_error(ret)
    info[:subject] = unsafe_string(pointer(read(bio)))
    ret = ccall((:X509_NAME_print_ex, libcrypto), Cint,
                (Ptr{Cvoid}, Ptr{Cvoid}, Cint, Culong),
                bio.data, ni, 0, XN_FLAG_ONELINE)
    openssl_error(ret)
    info[:issuer]  = unsafe_string(pointer(read(bio)))

    lastpos = Cint(-1)

    while true
        lastpos = ccall((:X509_NAME_get_index_by_NID, libcrypto), Cint,
                        (Ptr{Cvoid}, Cint, Cint), ns, NID_commonName, lastpos)
        lastpos == -1 && break
        e = ccall((:X509_NAME_get_entry, libcrypto), Ptr{Cvoid},
                  (Ptr{Cvoid}, Cint), ns, lastpos)
        ed = ccall((:X509_NAME_ENTRY_get_data, libcrypto), Ptr{Cvoid},
                   (Ptr{Cvoid}, ), e)
        ret = ccall((:ASN1_STRING_print_ex, libcrypto), Cint,
                    (Ptr{Cvoid}, Ptr{Cvoid}, Cint),
                    bio.data, ed, ASN1_STRFLGS_RFC2253)
        openssl_error(ret)
        cn = unsafe_string(pointer(read(bio)))
        cns = get!(info, :cn, CDTextString[])
        push!(cns, cn)
    end

    x509_notBefore = ccall((:X509_get0_notBefore, libcrypto), Ptr{Cvoid},
                           (Ptr{Cvoid}, ), c.data)
    ret = ccall((:ASN1_STRING_print, libcrypto), Cint,
                (Ptr{Cvoid}, Ptr{Cvoid}), bio.data, x509_notBefore)
    openssl_error(ret)
    info[:notBefore] = read_cddate(bio)

    x509_notAfter  = ccall((:X509_get0_notAfter,  libcrypto), Ptr{Cvoid},
                           (Ptr{Cvoid}, ), c.data)
    ret = ccall((:ASN1_STRING_print, libcrypto), Cint,
                (Ptr{Cvoid}, Ptr{Cvoid}), bio.data, x509_notAfter)
    openssl_error(ret)
    info[:notAfter]  = read_cddate(bio)
    info[:text] = string(c)
    return info
end

# Flags for X509_print_ex()

const X509_FLAG_COMPAT                =Cint(0)
const X509_FLAG_NO_HEADER             =Cint(1)
const X509_FLAG_NO_VERSION            =Cint(1 << 1)
const X509_FLAG_NO_SERIAL             =Cint(1 << 2)
const X509_FLAG_NO_SIGNAME            =Cint(1 << 3)
const X509_FLAG_NO_ISSUER             =Cint(1 << 4)
const X509_FLAG_NO_VALIDITY           =Cint(1 << 5)
const X509_FLAG_NO_SUBJECT            =Cint(1 << 6)
const X509_FLAG_NO_PUBKEY             =Cint(1 << 7)
const X509_FLAG_NO_EXTENSIONS         =Cint(1 << 8)
const X509_FLAG_NO_SIGDUMP            =Cint(1 << 9)
const X509_FLAG_NO_AUX                =Cint(1 << 10)
const X509_FLAG_NO_ATTRIBUTES         =Cint(1 << 11)
const X509_FLAG_NO_IDS                =Cint(1 << 12)

function show(io::IO, cert::PDCert)
    bio = BIO()
    ccall((:X509_print_ex, libcrypto), Cint,
          (Ptr{Cvoid}, Ptr{Cvoid}, Culong, Culong),
          bio.data, cert.data, XN_FLAG_ONELINE, X509_FLAG_COMPAT)
    ccall((:PEM_write_bio_X509, libcrypto), Cint,
          (Ptr{Cvoid}, Ptr{Cvoid}), bio.data, cert.data)
    return print(io, unsafe_string(pointer(read(bio))))
end

function get_signer_info(cmsinfo::CMSSignedInfo)
    cms = cmsinfo.cms
    certs = ccall((:CMS_get1_certs, libcrypto), Ptr{Cvoid},
                   (Ptr{Cvoid}, ), cms)
    num = ccall((:OPENSSL_sk_num, libcrypto), Cint, (Ptr{Cvoid}, ), certs)
    openssl_error(num)

    sinfos = ccall((:CMS_get0_SignerInfos, libcrypto), Ptr{Cvoid},
                   (Ptr{Cvoid}, ), cms)
    nsi = ccall((:OPENSSL_sk_num, libcrypto), Cint, (Ptr{Cvoid}, ), sinfos)
    @assert nsi == 1 "PDF specification requires only one SignerInfo"
    si = ccall((:OPENSSL_sk_value, libcrypto), Ptr{Cvoid},
               (Ptr{Cvoid}, Cint), sinfos, 0)
    return si
end

function get_signer_info_signing_time(si::Ptr{Cvoid})
    loc = ccall((:CMS_signed_get_attr_by_NID, libcrypto), Cint,
                (Ptr{Cvoid}, Cint, Cint), si, NID_pkcs9_signingTime, Cint(-1))
    loc < 0 && return nothing
    attr = ccall((:CMS_signed_get_attr, libcrypto), Ptr{Cvoid},
                 (Ptr{Cvoid}, Cint), si, loc)
    st_asn = ccall((:X509_ATTRIBUTE_get0_data, libcrypto), Ptr{Cvoid},
                   (Ptr{Cvoid}, Cint, Cint, Ptr{Cvoid}),
                   si, 0, V_ASN1_IA5STRING, C_NULL)
    st_asn == C_NULL && return nothing
    bio = BIO()
    ret = ccall((:ASN1_STRING_print, libcrypto), Cint,
                (Ptr{Cvoid}, Ptr{Cvoid}), bio.data, st_asn)
    openssl_error(ret)
    return read_cddate(bio)
end

function get_signer_info_timestamp(si::Ptr{Cvoid})
    loc = ccall((:CMS_unsigned_get_attr_by_NID, libcrypto), Cint,
                (Ptr{Cvoid}, Cint, Cint),
                si, NID_id_smime_aa_timeStampToken, Cint(-1))
    loc < 0 && return nothing
    attr = ccall((:CMS_unsigned_get_attr, libcrypto), Ptr{Cvoid},
                 (Ptr{Cvoid}, Cint), si, loc)
    attr == C_NULL && return nothing
    dptr = ccall((:X509_ATTRIBUTE_get0_data, libcrypto), Ptr{Cvoid},
                 (Ptr{Cvoid}, Cint, Cint, Ptr{Cvoid}),
                 attr, 0, V_ASN1_SEQUENCE, C_NULL)
    xder = Ref(Ptr{Cuchar}(C_NULL))
    len = ccall((:ASN1_STRING_length, libcrypto), Cint, (Ptr{Cvoid}, ), dptr)
    ptr = ccall((:ASN1_STRING_get0_data, libcrypto), Ptr{Cuchar},
                (Ptr{Cvoid}, ), dptr)
    xptr = Ref(ptr)
    ts = ccall((:d2i_CMS_ContentInfo, libcrypto), Ptr{Cvoid},
               (Ptr{Cvoid}, Ptr{Ptr{Cuchar}}, Clong), C_NULL, xptr, len)
    ts == C_NULL && return nothing
    eobj = ccall((:CMS_get0_eContentType, libcrypto), Ptr{Cvoid},
                   (Ptr{Cvoid}, ), ts)
    nid = ccall((:OBJ_obj2nid, libcrypto), Cint, (Ptr{Cvoid}, ), eobj)
    nid != NID_id_smime_ct_TSTInfo && return nothing
    ptinfo = ccall((:CMS_get0_content, libcrypto), Ptr{Ptr{Cvoid}},
                   (Ptr{Cvoid}, ), ts)
    tinfo = unsafe_load(ptinfo)
    tinfo == C_NULL && return nothing
    len  = ccall((:ASN1_STRING_length, libcrypto), Cint, (Ptr{Cvoid}, ), tinfo)
    cbuf = ccall((:ASN1_STRING_get0_data, libcrypto), Ptr{Cuchar},
                 (Ptr{Cuchar}, ), tinfo)
    tst_info = ccall((:d2i_TS_TST_INFO, libcrypto), Ptr{Cvoid},
                     (Ptr{Cvoid}, Ptr{Ptr{Cuchar}}, Clong),
                     C_NULL, Ref(cbuf), len)
    gentime = ccall((:TS_TST_INFO_get_time, libcrypto), Ptr{Cvoid},
                    (Ptr{Cvoid}, ), tst_info)
    bio = BIO()
    ret = ccall((:ASN1_STRING_print, libcrypto), Cint,
                    (Ptr{Cvoid}, Ptr{Cvoid}), bio.data, gentime)
    openssl_error(ret)
    return read_cddate(bio)
end

function harvest_certs(cmsinfo::CMSSignedInfo)
    cms = cmsinfo.cms
    certs = ccall((:CMS_get1_certs, libcrypto), Ptr{Cvoid},
                   (Ptr{Cvoid}, ), cms)
    num = ccall((:OPENSSL_sk_num, libcrypto), Cint, (Ptr{Cvoid}, ), certs)
    openssl_error(num)

    si = get_signer_info(cmsinfo)
    xcert = Ref(C_NULL)
    ccall((:CMS_SignerInfo_get0_algs, libcrypto), Cvoid,
          (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Ptr{Cvoid}}, Ptr{Cvoid}, Ptr{Cvoid}),
          si, C_NULL, xcert, C_NULL, C_NULL)
    signed_cert = PDCert(xcert[], nothing)

    certs_info = Vector{Dict{Symbol, Any}}()
    for i = 1:num
        cert = ccall((:OPENSSL_sk_value, libcrypto), Ptr{Cvoid},
                     (Ptr{Cvoid}, Cint), certs, i-1)
        # Take ownership of cert clean up
        pdc = PDCert(cert)
        push!(certs_info, get_info(pdc))
        if xcert[] == C_NULL
            ret = ccall((:CMS_SignerInfo_cert_cmp, libcrypto), Cint,
                        (Ptr{Cvoid}, Ptr{Cvoid}), si, cert)
            ret == 0 && (signed_cert = pdc)
        end
    end
    ccall((:OPENSSL_sk_free, libcrypto), Cvoid, (Ptr{Cvoid}, ), certs)
    return certs_info, signed_cert
end

mutable struct PDPKey
    data::Ptr{Cvoid}
    function PDPKey(cert::PDCert)
        kdata = ccall((:X509_get_pubkey, libcrypto), Ptr{Cvoid},
                      (Ptr{Cvoid}, ), cert.data)
        kdata == C_NULL && error("Cannot extract public key from certificate")
        this = new(kdata)
        finalizer(x->ccall((:EVP_PKEY_free, libcrypto),
                           Cvoid, (Ptr{Cvoid}, ), x.data), this)
        return this
    end
end

Base.:(==)(k1::PDPKey, k2::PDPKey) = 
    ccall((:EVP_PKEY_cmp, libcrypto), Cint,
          (Ptr{Cvoid}, Ptr{Cvoid}), k1.data, k2.data) == 1

const X509_V_FLAG_IGNORE_CRITICAL = Cint(0x10)

function verify_local_trust(store::PDCertStore, cert::PDCert)
    ret = find_cert(store, cert)
    !ret && is_self_signed(cert) &&
        error("Self-signed cert not found in certificate trust store")
    return ret
end

# Verification of certificate validity
function verify!(status::Dict{Symbol, Any}, cert::PDCert, store::PDCertStore)
    crt_info = get_info(cert)
    vrf_chain = get!(status, :certs, Dict{Symbol, Any}[])
    push!(vrf_chain, crt_info)
    if verify_local_trust(store, cert)
        crt_info = get_info(cert)
        vrf_chain = get!(status, :chain, Dict{Symbol, Any}[])
        push!(vrf_chain, crt_info)
        status[:passed] = true
        return true
    end
    ctx = ccall((:X509_STORE_CTX_new, libcrypto), Ptr{Cvoid}, ())
    param = C_NULL
    try
        # The signing time for validation as PKCS-1 does not have a timestamp.
        # Hence, the PDF atrribute is used.
        
        st = get(status, :M, nothing)
        if st !== nothing
            st = getUTCTime(st)
            t = datetime2unix(st.d)
            d = (:atepoch => t)
            set_params(store, d)
        end

        ret = ccall((:X509_STORE_CTX_init, libcrypto), Cint,
                    (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}),
                    ctx, store.data, cert.data, C_NULL)
        openssl_error(ret)
        
        ret = ccall((:X509_verify_cert, libcrypto), Cint, (Ptr{Cvoid}, ), ctx)
        if ret <= 0
            depth = ccall((:X509_STORE_CTX_get_error_depth, libcrypto), Cint,
                          (Ptr{Cvoid}, ), ctx)
            err   = ccall((:X509_STORE_CTX_get_error, libcrypto), Cint,
                          (Ptr{Cvoid}, ), ctx)
            cestr = ccall((:X509_verify_cert_error_string, libcrypto),
                          Cstring, (Cint, ), err)
            errstr = unsafe_string(cestr)
            status[:passed] = false
            status[:error_message]  = errstr
        else
            chain = ccall((:X509_STORE_CTX_get1_chain, libcrypto), Ptr{Cvoid},
                          (Ptr{Cvoid}, ), ctx)
            num = ccall((:OPENSSL_sk_num, libcrypto), Cint,
                        (Ptr{Cvoid}, ), chain)
            for i = 0:(num-1)
                cert = ccall((:OPENSSL_sk_value, libcrypto), Ptr{Cvoid},
                             (Ptr{Cvoid}, Cint), chain, i)
                pdc = PDCert(cert, nothing)
                crt_info = get_info(pdc)
                vrf_chain = get!(status, :chain, Dict{Symbol, Any}[])
                push!(vrf_chain, crt_info)
                ccall((:X509_free, libcrypto), Cvoid, (Ptr{Cvoid},), cert)
            end
            ccall((:OPENSSL_sk_free, libcrypto), Cvoid, (Ptr{Cvoid}, ), chain)
            status[:passed] = true
        end
    finally
        ccall((:X509_VERIFY_PARAM_free, libcrypto), Cvoid, (Ptr{Cvoid}, ), param)
        ccall((:X509_STORE_CTX_free, libcrypto), Cvoid, (Ptr{Cvoid}, ), ctx)
    end
    return status[:passed]
end

const RSA_PKCS1_PADDING = Cint(1)

function verify!(status::Dict{Symbol, Any}, si::PKCS1SignedInfo, cert::PDCert,
                 store::PDCertStore)
    verify!(status, cert, store)
    status[:passed] || return
    pkey = PDPKey(cert)
    doc, brange, sdata = si.doc, si.brange, si.sdata

    rsa = ccall((:EVP_PKEY_get0_RSA, libcrypto), Ptr{Cvoid},
                (Ptr{Cvoid}, ), pkey.data)
    rsa == C_NULL && error("Invalid RSA certificate")

    len = ccall((:RSA_size, libcrypto), Cint, (Ptr{Cvoid}, ), rsa) - 11
    out = Vector{UInt8}(undef, len)
    len = ccall((:RSA_public_decrypt, libcrypto), Cint,
                (Cint, Ptr{Cuchar}, Ptr{Cuchar}, Ptr{Cvoid}, Cint),
                length(sdata), pointer(sdata), pointer(out), rsa,
                RSA_PKCS1_PADDING)
    openssl_error(len)

    # X509_SIG is recommendeded to be used for DigestInfo
    sig = ccall((:d2i_X509_SIG, libcrypto), Ptr{Cvoid},
                (Ptr{Cvoid}, Ptr{Ptr{Cuchar}}, Clong),
                C_NULL, Ref(pointer(out)), len)
    try
        xalgor, xdigest = Ref(C_NULL), Ref(C_NULL)
        ccall((:X509_SIG_get0, libcrypto), Cvoid,
              (Ptr{Cvoid}, Ptr{Ptr{Cvoid}}, Ptr{Ptr{Cvoid}}),
              sig, xalgor, xdigest)

        # Digest data extraction from X509_SIG
        c_digest = ccall((:ASN1_STRING_get0_data, libcrypto), Ptr{Cuchar},
                         (Ptr{Cvoid}, ), xdigest[])
        c_len = ccall((:ASN1_STRING_length, libcrypto), Cint,
                      (Ptr{Cvoid}, ), xdigest[])
        xtract_digest = Vector{UInt8}(undef, c_len)
        unsafe_copyto!(pointer(xtract_digest), c_digest, c_len)    

        # Compute digest from PDF file data applying the hash algorithm
        # available in the PKCS#1 signature
        xoid, xvtyp, xpval = Ref(C_NULL), Ref(Cint(0)), Ref(C_NULL)
        ccall((:X509_ALGOR_get0, libcrypto), Cvoid,
              (Ptr{Ptr{Cvoid}}, Ptr{Cint}, Ptr{Ptr{Cvoid}}, Ptr{Cvoid}),
              xoid, xvtyp, xpval, xalgor[])

        nid = ccall((:OBJ_obj2nid, libcrypto), Cint, (Ptr{Cvoid}, ), xoid[])
        cstr_sn  = ccall((:OBJ_nid2sn, libcrypto), Cstring, (Cint, ), nid)
        sn = unsafe_string(cstr_sn)
        compute_digest = get_message_digest(doc, brange, sn)
        status[:passed] = res = (xtract_digest == compute_digest)
        !res && error("Computed digest is not the same as in the signature")
    finally
        ccall((:X509_SIG_free, libcrypto), Cvoid, (Ptr{Cvoid}, ), sig)
    end
end

const CMS_TEXT                   = Cint(0x1)
const CMS_NOCERTS                = Cint(0x2)
const CMS_NO_CONTENT_VERIFY      = Cint(0x4)
const CMS_NO_ATTR_VERIFY         = Cint(0x8)
const CMS_NOSIGS                 = CMS_NO_CONTENT_VERIFY +
                                   CMS_NO_ATTR_VERIFY
const CMS_NOINTERN               = Cint(0x10)
const CMS_NO_SIGNER_CERT_VERIFY  = Cint(0x20)
const CMS_NOVERIFY               = Cint(0x20)
const CMS_DETACHED               = Cint(0x40)
const CMS_BINARY                 = Cint(0x80)
const CMS_NOATTR                 = Cint(0x100)
const CMS_NOSMIMECAP             = Cint(0x200)
const CMS_NOOLDMIMETYPE          = Cint(0x400)
const CMS_CRLFEOL                = Cint(0x800)
const CMS_STREAM                 = Cint(0x1000)
const CMS_NOCRL                  = Cint(0x2000)
const CMS_PARTIAL                = Cint(0x4000)
const CMS_REUSE_DIGEST           = Cint(0x8000)
const CMS_USE_KEYID              = Cint(0x10000)
const CMS_DEBUG_DECRYPT          = Cint(0x20000)
const CMS_KEY_PARAM              = Cint(0x40000)
const CMS_ASCIICRLF              = Cint(0x80000)
const CMS_CADES                  = Cint(0x100000)

function verify!(status::Dict{Symbol, Any}, si::CMSSignedInfo, ::Nothing,
                 store::PDCertStore)
    detached, bio = si.detached, C_NULL
    hdata = Vector{UInt8}(undef, 0)
    if detached
        doc, brange = si.doc, si.brange
        for i = 1:2:length(brange)
            buff = readfrom(doc.cosDoc, brange[i], brange[i+1])
            append!(hdata, buff)
        end
    else
        hdata = get_message_digest(si.doc, si.brange, "SHA1")
    end

    status[:certs], signed_cert = harvest_certs(si)

    signer_info = get_signer_info(si)
    # Deciding signing time the order of values to be picked up
    # 1. Signing time attribute from the signed attributes of signer info
    # 2. Time attribute picked up from the timestamp
    # 3. Time attribute picked up from the PDF dictionary
    st = get_signer_info_signing_time(signer_info)
    st === nothing && (st = get_signer_info_timestamp(signer_info))
    st === nothing && (st = get(status, :M, nothing))
    if st !== nothing
        st = getUTCTime(st)
        t = datetime2unix(st.d)
        d = Dict(:atepoch => t)
        set_params(store, d)
    end
    flags = CMS_BINARY
    verify_local_trust(store, signed_cert) &&
        (flags |= CMS_NO_SIGNER_CERT_VERIFY)
    status[:subfilter] === cn"ETSI.CAdES.detached" &&
        (flags |= CMS_CADES)
    ret = ccall((:CMS_verify, libcrypto), Cint,
                (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid},
                 Ptr{Cvoid}, Ptr{Cvoid}, Cint),
                si.cms, C_NULL, store.data, BIO(hdata).data, C_NULL, flags)
    openssl_error(ret)
    pdcert = get_signer(si)
    chain = get!(status, :chain, Dict{Symbol, Any}[])
    push!(chain, si |> get_signer |> get_info)
    return (status[:passed] = true)
end

function pd_validate_signature(doc::PDDocImpl,
                               sig::Tuple{IDD{CosDict}, Dict{Symbol, Any}})
    status = sig[2]
    status[:passed] = false
    sigdict = cosDocGetObject(doc.cosDoc, sig[1], cn"V")
    sigdict === CosNull && return status[:passed]
    subfilter = cosDocGetObject(doc.cosDoc, sigdict, cn"SubFilter")
    !(subfilter in (cn"adbe.x509.rsa_sha1",
                    cn"adbe.pkcs7.detached",
                    cn"adbe.pkcs7.sha1",
                    cn"ETSI.CAdES.detached",
                    cn"ETSI.RFC3161")) && return false
    bobj = cosDocGetObject(doc.cosDoc, sigdict, cn"ByteRange")
    bobj === CosNull && return status[:passed]
    brange = get(bobj, true)
    cobj = cosDocGetObject(doc.cosDoc, sigdict, cn"Contents")
    cobj === CosNull && return status[:passed]
    contents = Vector{UInt8}(cobj)
    si, cert = nothing, nothing

    try
        status[:subfilter] = subfilter
        if subfilter === cn"adbe.pkcs7.sha1"
            si = CMSSignedInfo(doc, brange, contents)
        elseif subfilter === cn"adbe.pkcs7.detached" ||
            subfilter === cn"ETSI.CAdES.detached"
            si = CMSSignedInfo(doc, brange, contents, true)
        elseif subfilter === cn"adbe.x509.rsa_sha1"
            si = PKCS1SignedInfo(doc, brange, contents)
            cert_obj = cosDocGetObject(doc.cosDoc, sigdict, cn"Cert")
            cdata = Vector{UInt8}(cert_obj)
            cert = PDCert(cdata)
        end

        name_obj = cosDocGetObject(doc.cosDoc, sigdict, cn"Name")
        if name_obj !== CosNull
            status[:Name] = CDTextString(name_obj)
        end
        m_obj    = cosDocGetObject(doc.cosDoc, sigdict, cn"M")
        if m_obj !== CosNull
            status[:M] = CDDate(CDTextString(m_obj))
        end
        store = PDCertStore()
        verify!(status, si, cert, store)
    catch e
        delete!(status, :chain)
        status[:passed] = false
        status[:error_message] = e.msg
        status[:stacktrace] = string.(stacktrace(catch_backtrace()))
    end
    return status[:passed]
end
