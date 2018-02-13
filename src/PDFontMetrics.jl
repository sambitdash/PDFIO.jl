# This file has methods to read font metrics for Base-14 fonts
#Currently only the width metric is used.
using ..Cos
using IntervalTrees

mutable struct AdobeFontMetrics
    cid_to_name::Dict{Int, CosName}
    name_to_wx::Dict{CosName, Int}
    name_to_b::Dict{CosName, Vector{Int}}
    kern_pairs::Dict{Tuple{CosName, CosName}, Tuple{Int, Int}}
    has_kerning::Bool
    AdobeFontMetrics() = new(Dict{Int, CosName}(),
                             Dict{CosName, Int}(),
                             Dict{CosName, Vector{Int}}(),
                             Dict{Tuple{CosName, CosName}, Tuple{Int, Int}}(),
                             false)
end

function interpret_metric_line(line::AbstractString)
    tokens = split(line, ';'; keep=false)
    cid = -1; wx = 1000; n = "null"; bb = [0,0,0,0]
    for token in tokens
        v = split(strip(token), ' '; limit = 2)
        m = strip(v[1])
        val = strip(v[2])
        if m == "C"
            cid = parse(Int, val)
        elseif m == "CH"
            val = rstrip(replace(val, "<", "0x"), '>')
            cid = parse(Int, val)
        elseif m == "WX"
            wx = parse(Int, val)
        elseif m == "N"
            n = val
        elseif m == "B"
            rr = split(val)
            bb = parse.(Int, [rr[1], rr[2], rr[3], rr[4]])
        end
    end
    return (cid, wx, CosName(n), bb)
end

function populate_char_metrics(lines, state, afm, nLines)
    nLineRead = 0
    (line, state) = next(lines, state)
    while nLineRead < nLines
        cid, wx, n, b = interpret_metric_line(line)
        if cid > -1
            afm.cid_to_name[cid] = n
        end
        afm.name_to_wx[n] = wx
        afm.name_to_b[n] = b
        nLineRead += 1
        (line, state) = next(lines, state)
    end
end

function interpret_kerpair_line(line::AbstractString)
    tokens = split(line)
    key = tokens[1]
    return CosName(tokens[2]), CosName(tokens[3]), parse(Int,tokens[4]),
            (key == "KP") || (key == "KPH") ? parse(Int, tokens[5]) : 0
end

function populate_kern_pairs(lines, state, afm, nLines)
    nLineRead = 0
    (line, state) = next(lines, state)
    while nLineRead < nLines
        n1, n2, x, y = interpret_kerpair_line(line)
        afm.kern_pairs[(CosName(n1), CosName(n2))] = (x, y)
        nLineRead += 1
        (line, state) = next(lines, state)
    end
    afm.has_kerning = true
end

function read_afm(fontname::AbstractString)
    d_name_w = Dict{CosName, Int}()
    d_cid_w = Dict{Int, Int}()
    filename = fontname * ".afm"
    path = joinpath(Pkg.dir("PDFIO"), "data", "fonts", filename)
    lines = readlines(path)
    bStartCharMetrics = false
    bReadKernPairs = false
    nMetrics = 0
    nLineRead = 0
    afm = AdobeFontMetrics()
    state = start(lines)
    while !done(lines, state)
        (line, state) = next(lines, state)
        bStartCharMetrics = startswith(line, "StartCharMetrics")
        bReadKernPairs = startswith(line, "StartKernPairs")
        if bStartCharMetrics || bReadKernPairs
            v = split(line)
            n = parse(Int, v[2])
            if bStartCharMetrics
                populate_char_metrics(lines, state, afm, n)
                bStartCharMetrics = false
            end
            if bReadKernPairs
                populate_kern_pairs(lines, state, afm, n)
                bReadKernPairs = false
            end
        end
    end
    return afm
end

get_font_widths(cosdoc::CosDoc, font::CosNullType) = zeros(Int, 256)

function get_font_widths(cosdoc::CosDoc, font::CosObject)
    d = zeros(Int, 256)
    @assert get(font, cn"Type") === cn"Font"
    subtype = get(font, cn"Subtype")
    (subtype === cn"Type0") && return get_cid_font_widths(cosdoc, font)
    basefont = get(font, cn"BaseFont")
    widths_obj = cosDocGetObject(cosdoc, font, cn"Widths")
    widths_obj === CosNull && return get_font_widths(basefont)
    firstchar = get(font, cn"FirstChar") |> get
    lastchar  = get(font, cn"LastChar")  |> get
    @assert lastchar < 256
    widths = get(widths_obj, true)
    for i = firstchar:lastchar
        ix = i - firstchar + 1
        d[i+1] = widths[ix]
    end
    return d
end

get_font_widths(basefonts::CosName) = read_afm(convert(CDTextString, basefonts))

function get_cid_font_widths(cosDoc::CosDoc, font::CosObject)
    m = IntervalMap{UInt16, Int}()
    encoding = cosDocGetObject(cosDoc, font, cn"Encoding")
    desc = cosDocGetObject(cosDoc, font, cn"DescendantFonts") |> get
    w = cosDocGetObject(cosDoc, desc[1], cn"W")
    dw = cosDocGetObject(cosDoc, desc[1], cn"DW")
    # If widths are not specified or the font encoding is not Identity-H
    # widths cannot be extracted.
    if w === CosNull || encoding != cn"Identity-H"
        return (dw === CosNull) ? CIDWidth() : CIDWidth(get(dw))
    end
    w = get(w)
    state = start(w)
    while !done(w, state)
        (i, state) = next(w, state)
        bcid = get(i)
        (i, state) = next(w, state)
        ecid = get(i)
        ccid = bcid
        if ecid isa Vector
            for wdo in ecid
                width = get(wdo)
                m[(UInt16(ccid), UInt16(ccid))] = width
                ccid += 1
            end
        else
            (width, state) = next(w, state)
            m[(UInt16(bcid), UInt16(ecid))] = width
        end
    end
    return (dw === CosNull) ? CIDWidth(m) : CIDWidth(m, get(dw))
end

get_character_width(n::CosName, afm::AdobeFontMetrics) = get(afm.name_to_wx, n, 1000)
get_character_width(cid::Int, afm::AdobeFontMetrics) =
    get_character_width(get(afm.cid_to_name, cid, nothing), afm)
get_character_width(Void, afm::AdobeFontMetrics) = 1000

get_kern_width(c1::Int, c2::Int, afm::AdobeFontMetrics) =
    get_kern_width(get(afm.cid_to_name, c1, nothing),
                   get(afm.cid_to_name, c2, nothing),
                   afm)
get_kern_width(n1::CosName, n2::CosName, afm::AdobeFontMetrics) =
    get(afm.kern_pairs, (n1, n2), (0, 0))[1]
get_kern_width(c1, ::Void, other) = 0
get_kern_width(::Void, c2, other) = 0
get_kern_width(::Void, ::Void, ::Any) = 0
get_kern_width(c1, c2, other) = 0

get_character_width(cid::UInt8, widths::Vector) =
    (widths[Int(cid+1)] == 0) ? 1000 : widths[Int(cid+1)]
