using Dates
using ..Common

function get_message_digest(doc::PDDoc, brange::Vector{Int}, algo::String)
    ctx = DigestContext(algo)
    for i = 1:2:length(brange)
        buff = readfrom(doc.cosDoc, brange[i], brange[i+1])
        update!(ctx, buff)
    end
    return close(ctx)
end

function verify_local_trust(store::CertStore, cert::Cert)
    ret = find_cert(store, cert)
    !ret && is_self_signed(cert) &&
        error("Self-signed cert not found in certificate trust store")
    return ret
end

# Verification of certificate validity
function verify!(status::Dict{Symbol, Any}, cert::Cert, store::CertStore)
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
    # The signing time for validation as PKCS-1 does not have a timestamp.
    # Hence, the PDF atrribute is used.
    st = get(status, :M, nothing)
    if st !== nothing
        st = getUTCTime(st)
        t = datetime2unix(st.d)
        d = (:atepoch => t)
        set_params!(store, d)
    end

    passed, data = verify(store, cert)
    status[:passed] = passed
    if passed
        status[:chain] = data
    else
        status[:error_message] = data
    end
    return status[:passed]
end

function verify!(status::Dict{Symbol, Any}, si::PKCS1SignedInfo, cert::Cert,
                 store::CertStore, doc::PDDoc, brange::Vector{Int})
    verify!(status, cert, store)
    status[:passed] || return
    xtract_digest, digest_algo = get_rsa_digest(si, cert)
    compute_digest = get_message_digest(doc, brange, digest_algo)
    status[:passed] = res = (xtract_digest == compute_digest)
    !res && error("Computed digest is not the same as in the signature")
end

function verify!(status::Dict{Symbol, Any}, si::CMSSignedInfo, ::Nothing,
                 store::CertStore, doc::PDDoc, brange::Vector{Int})
    detached, bio = si.detached, C_NULL
    hdata = Vector{UInt8}(undef, 0)
    if detached
        for i = 1:2:length(brange)
            buff = readfrom(doc.cosDoc, brange[i], brange[i+1])
            append!(hdata, buff)
        end
    else
        hdata = get_message_digest(doc, brange, "SHA1")
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
        set_params!(store, d)
    end
    flags = Cint(CMS_BINARY)
    verify_local_trust(store, signed_cert) &&
        (flags |= CMS_NO_SIGNER_CERT_VERIFY)
    status[:subfilter] === cn"ETSI.CAdES.detached" && (flags |= CMS_CADES)
    verify(si, store, hdata, flags)
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
    # This should not go through document security handler.
    # Hence, direct COS method. DO NOT USE cosDocGetObject.
    cobj = get(sigdict, cn"Contents")
    cobj === CosNull && return status[:passed]
    contents = Vector{UInt8}(cobj)
    si, cert = nothing, nothing

    try
        status[:subfilter] = subfilter
        if subfilter === cn"adbe.pkcs7.sha1"
            si = CMSSignedInfo(contents)
        elseif subfilter === cn"adbe.pkcs7.detached" ||
            subfilter === cn"ETSI.CAdES.detached"
            si = CMSSignedInfo(contents, true)
        elseif subfilter === cn"adbe.x509.rsa_sha1"
            si = PKCS1SignedInfo(contents)
            cert_obj = cosDocGetObject(doc.cosDoc, sigdict, cn"Cert")
            cdata = Vector{UInt8}(cert_obj)
            cert = Cert(cdata)
        end

        name_obj = cosDocGetObject(doc.cosDoc, sigdict, cn"Name")
        if name_obj !== CosNull
            status[:Name] = CDTextString(name_obj)
        end
        m_obj    = cosDocGetObject(doc.cosDoc, sigdict, cn"M")
        if m_obj !== CosNull
            status[:M] = CDDate(CDTextString(m_obj))
        end
        store = CertStore()
        verify!(status, si, cert, store, doc, brange)
    catch e
        delete!(status, :chain)
        status[:passed] = false
        status[:error_message] = e.msg
        status[:stacktrace] = string.(stacktrace(catch_backtrace()))
    end
    return status[:passed]
end
