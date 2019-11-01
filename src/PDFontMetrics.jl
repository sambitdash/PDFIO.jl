# This file has methods to read font metrics for Base-14 fonts
#Currently only the width metric is used.
using ..Cos

using Rectangle

const ADOBE_STD_14 = Set(
["Times-Roman",      "Helvetica",             "Courier",         "Symbol",
 "Times-Bold",       "Helvetica-Bold",        "Courier-Bold",    "ZapfDingbats",
 "Times-Italic",     "Helvetica-Oblique",     "Courier-Oblique",
 "Times-BoldItalic", "Helvetica-BoldOblique", "Courier-BoldOblique"])

mutable struct AdobeFontMetrics
    cid_to_name::Dict{Int, CosName}
    name_to_wx::Dict{CosName, Float32}
    name_to_b::Dict{CosName, Vector{Int}}
    kern_pairs::Dict{Tuple{CosName, CosName}, Tuple{Float32, Float32}}
    has_kerning::Bool
    italicAngle::Float32
    isFixedPitch::Bool
    weight::Symbol
    fontname::CosName

    AdobeFontMetrics() = new(Dict{Int, CosName}(),
                             Dict{CosName, Int}(),
                             Dict{CosName, Vector{Int}}(),
                             Dict{Tuple{CosName, CosName},
                                  Tuple{Float32, Float32}}(),
                             false,
                             0,
                             false,
                             :Medium,
                             cn""
                             )
end

isBold(afm::AdobeFontMetrics)   = afm.weight === :Bold
isItalic(afm::AdobeFontMetrics) = afm.italicAngle != 0
isFixedW(afm::AdobeFontMetrics) = afm.isFixedPitch

get_font_name(afm::AdobeFontMetrics) = afm.fontname

function get_font_flags(afm::AdobeFontMetrics)
    res = 0x00000000
    isItalic(afm) && (res += 0x00000040)
    isFixedW(afm) && (res += 0x00000001)
    return res
end

function interpret_metric_line(line::AbstractString)
    tokens = split(line, ';'; keepempty=false)
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
    (line, state) = iterate(lines, state)
    while nLineRead < nLines
        cid, wx, n, b = interpret_metric_line(line)
        if cid > -1
            afm.cid_to_name[cid] = n
        end
        afm.name_to_wx[n] = Float32(wx)
        afm.name_to_b[n] = b
        nLineRead += 1
        (line, state) = iterate(lines, state)
    end
end

function interpret_kerpair_line(line::AbstractString)
    tokens = split(line)
    key = tokens[1]
    a = CosName(tokens[2])
    b = CosName(tokens[3])
    x = key in ("KP", "KPH", "KPX") ? parse(Float32, tokens[4]) : 0f0
    y = key in ("KP", "KPH", "KPY") ? parse(Float32, tokens[5]) : 0f0
    return a, b, x, y
end

function populate_kern_pairs(lines, state, afm, nLines)
    nLineRead = 0
    (line, state) = iterate(lines, state)
    while nLineRead < nLines
        n1, n2, x, y = interpret_kerpair_line(line)
        afm.kern_pairs[(n1, n2)] = (x, y)
        nLineRead += 1
        (line, state) = iterate(lines, state)
    end
    afm.has_kerning = true
end

function read_afm(fontname::AbstractString)
    d_name_w = Dict{CosName, Int}()
    d_cid_w = Dict{Int, Int}()
    filename = fontname * ".afm"
    path = joinpath(@__DIR__, "..", "data", "fonts", filename)
    lines = readlines(path)
    bStartCharMetrics = false
    bReadKernPairs = false
    nMetrics = 0
    nLineRead = 0
    afm = AdobeFontMetrics()
    next = iterate(lines)
    while next !== nothing
        (line, state) = next
        if startswith(line, "ItalicAngle")
            v = split(line)
            afm.italicAngle = parse(Float32, v[2])
        elseif startswith(line, "IsFixedPitch")
            v = split(line)
            afm.isFixedPitch = parse(Bool, v[2])
        elseif startswith(line, "FontName")
            v = split(line)
            afm.fontname = CosName(v[2])
        elseif startswith(line, "Weight")
            v = split(line)
            afm.weight = Symbol(v[2])
        else
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
        next = iterate(lines, state)
    end
    return afm
end

get_font_widths(cosdoc::CosDoc, font::CosNullType) = zeros(Float32, 256)

function get_font_widths(cosdoc::CosDoc, font::IDD{CosDict})
    d = zeros(Float32, 256)
    @assert cosDocGetObject(cosdoc, font, cn"Type") === cn"Font"
    subtype = cosDocGetObject(cosdoc, font, cn"Subtype")
    (subtype === cn"Type0") && return get_cid_font_widths(cosdoc, font)
    basefont = cosDocGetObject(cosdoc, font, cn"BaseFont")
    widths_obj = cosDocGetObject(cosdoc, font, cn"Widths")
    widths_obj === CosNull && return get_font_widths(basefont)
    firstchar = get(font, cn"FirstChar") |> get
    lastchar  = get(font, cn"LastChar")  |> get
    @assert lastchar < 256
    widths = get(widths_obj, true)
    for i = firstchar:lastchar
        ix = i - firstchar + 1
        d[i+1] = round(Int, widths[ix])
    end
    return d
end

get_font_widths(basefonts::CosName) = read_afm(convert(CDTextString, basefonts))

function get_cid_font_widths(cosDoc::CosDoc, font::IDDRef{CosDict})
    m = IntervalTree{UInt16, Float32}()
    encoding = cosDocGetObject(cosDoc, font, cn"Encoding")
    desc = cosDocGetObject(cosDoc, font, cn"DescendantFonts") |> get
    w = cosDocGetObject(cosDoc, desc[1], cn"W")
    dw = cosDocGetObject(cosDoc, desc[1], cn"DW")
    # If widths are not specified or the font encoding is not Identity-H
    # widths cannot be extracted.
    if w === CosNull || encoding != cn"Identity-H"
        return (dw === CosNull) ? CIDWidth() : CIDWidth(Float32(get(dw)))
    end
    w = get(w)
    next = iterate(w)
    while next !== nothing
        (i, state) = next
        bcid = get(i)
        next = iterate(w, state)
        (i, state) = next
        ecid = get(i)
        ccid = bcid
        if ecid isa Vector
            for wdo in ecid
                width = get(wdo)
                m[Interval(UInt16(ccid), UInt16(ccid))] = Float32(width)
                ccid += 1
            end
        else
            (width, state) = iterate(w, state)
            m[Interval(UInt16(bcid), UInt16(ecid))] = Float32(get(width))
        end
        next = iterate(w, state)
    end
    return (dw === CosNull) ? CIDWidth(m) : CIDWidth(m, Float32(get(dw)))
end

get_character_width(n::CosName, afm::AdobeFontMetrics) =
    get(afm.name_to_wx, n, 1000f0)
get_character_width(cid::UInt8, afm::AdobeFontMetrics) =
    get_character_width(get(afm.cid_to_name, cid, nothing), afm)
get_character_width(::Nothing, afm::AdobeFontMetrics) = 1000f0

get_kern_width(c1::Int, c2::Int, afm::AdobeFontMetrics) =
    get_kern_width(get(afm.cid_to_name, c1, nothing),
                   get(afm.cid_to_name, c2, nothing),
                   afm)
get_kern_width(n1::CosName, n2::CosName, afm::AdobeFontMetrics) =
    get(afm.kern_pairs, (n1, n2), (0f0, 0f0))[1]
get_kern_width(c1, ::Nothing, other) = 0f0
get_kern_width(::Nothing, c2, other) = 0f0
get_kern_width(::Nothing, ::Nothing, ::Any) = 0f0
get_kern_width(c1, c2, other) = 0f0

get_character_width(cid::UInt8, widths::Vector) =
    (widths[Int(cid+1)] == 0) ? 1000f0 : widths[Int(cid+1)]
