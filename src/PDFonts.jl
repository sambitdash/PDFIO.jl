import ..Cos: CosXString

export pdFontIsBold,
    pdFontIsItalic,
    pdFontIsFixedW,
    pdFontIsAllCap,
    pdFontIsSmallCap

using Rectangle


#=
Sample CMaps are available now as 8.cmap and 16.cmap in the test/files directory
for 8 and 16-bit toUnicode CMaps.
CMaps can have both 8 and 16 bit ranges in the same CMap file as well.
=#

const beginbfchar = b"beginbfchar"
const endbfchar   = b"endbfchar"
const beginbfrange = b"beginbfrange"
const endbfrange = b"endbfrange"
const begincodespacerange = b"begincodespacerange"
const endcodespacerange = b"endcodespacerange"


mutable struct CMap
    code_space::IntervalTree{UInt8,
                             Union{CosNullType, IntervalTree{UInt8, CosNullType}}}
    range_map::IntervalTree{UInt8,
                            Union{CosObject, IntervalTree{UInt8, CosObject}}}
    function CMap()
        cs = IntervalTree{UInt8,
                          Union{CosNullType, IntervalTree{UInt8, CosNullType}}}()
        rm = IntervalTree{UInt8,
                          Union{CosObject, IntervalTree{UInt8, CosObject}}}()
        new(cs, rm)
    end
end

function show(io::IO, cmap::CMap)
    show(io, "Code Space:\n")
    show(io, cmap.code_space)
    show(io, "Range Map:\n")
    show(io, cmap.range_map)
end

mutable struct FontUnicodeMapping
    encoding::Dict
    cmap::CMap
    hasCMap::Bool
    FontUnicodeMapping() = new(Dict(), CMap(), false)
end

function merge_encoding!(fum::FontUnicodeMapping, encoding::CosName,
                         doc::CosDoc, font::IDDRef{CosDict})
    encoding_mapping =
        encoding == cn"WinAnsiEncoding"   ? WINEncoding_to_Unicode :
        encoding == cn"MacRomanEncoding"  ? MACEncoding_to_Unicode :
        encoding == cn"MacExpertEncoding" ? MEXEncoding_to_Unicode :
                                            STDEncoding_to_Unicode
    merge!(fum.encoding, encoding_mapping)
    return fum
end

# for type 0 use cmap.
# for symbol and zapfdingbats - use font encoding
# for others use STD Encoding
# Reading encoding from the font files in case of Symbolic fonts are not
# supported.
# Font subset is addressed with font name identification.
function merge_encoding!(fum::FontUnicodeMapping, encoding::CosNullType,
                        doc::CosDoc, font::IDDRef{CosDict})
    subtype  = cosDocGetObject(doc, font, cn"Subtype")
    subtype !== cn"Type1" && subtype !== cn"MMType1" && return fum
    basefont = cosDocGetObject(doc, font, cn"BaseFont")
    basefont_with_subset = CDTextString(basefont)
    basefont_str = rsplit(basefont_with_subset, '+';limit=2)[end]
    enc = basefont_str == "Symbol"       ? SYMEncoding_to_Unicode :
          basefont_str == "ZapfDingbats" ? ZAPEncoding_to_Unicode :
                                           STDEncoding_to_Unicode
    merge!(fum.encoding, enc)
    return fum
end

function merge_encoding!(fum::FontUnicodeMapping,
                         encoding::IDD{CosDict},
                         doc::CosDoc, font::IDDRef{CosDict})
    baseenc = cosDocGetObject(doc, encoding, cn"BaseEncoding")
    merge_encoding!(fum, baseenc, doc, font)
    # Add the Differences
    diff = cosDocGetObject(doc, encoding, cn"Differences")
    diff === CosNull && return fum
    values = get(diff)
    d = Dict()
    cid = -1
    for v in values
        if v isa CosInt
            cid = get(v)
        else
            @assert cid != -1
            d[cid] = v
            cid += 1
        end
    end
    dict_to_unicode = dict_remap(d, AGL_Glyph_to_Unicode)
    merge!(fum.encoding, dict_to_unicode)
    return fum
end

function merge_encoding!(fum::FontUnicodeMapping, doc::CosDoc,
                         font::IDDRef{CosDict})
    encoding = cosDocGetObject(doc, font, cn"Encoding")
    merge_encoding!(fum, encoding, doc, font)
    toUnicode = cosDocGetObject(doc, font, cn"ToUnicode")
    toUnicode == CosNull && return fum
    merge_encoding!(fum, toUnicode, doc, font)
end

function merge_encoding!(fum::FontUnicodeMapping,
                         cmap::CosIndirectObject{CosStream},
                         doc::CosDoc, font::IDDRef{CosDict})
    stm_cmap = get(cmap)
    try
        fum.cmap = read_cmap(stm_cmap)
        fum.hasCMap = true
    finally
        util_close(stm_cmap)
    end
    return fum
end

function update_glyph_id_std_14(cosfont, glyph_name_to_cid, cid_to_glyph_name)
    basefont = get(cosfont, cn"BaseFont")
    basefont === CosNull && return false
    String(basefont) in ADOBE_STD_14 || return false
    gn2cid, cid2gn =
        basefont === cn"Symbol" ?
        (GlyphName_to_SYMEncoding, SYMEncoding_to_GlyphName) :
        basefont === cn"ZapfDingbats" ?
        (GlyphName_to_ZAPEncoding, ZAPEncoding_to_GlyphName) :
        (GlyphName_to_STDEncoding, STDEncoding_to_GlyphName)
    merge!(glyph_name_to_cid, gn2cid)
    merge!(cid_to_glyph_name, cid2gn)
    return true
end

function get_glyph_id_mapping(cosdoc::CosDoc, cosfont::IDD{CosDict})
    glyph_name_to_cid, cid_to_glyph_name =
        Dict{CosName, UInt8}(), Dict{UInt8, CosName}()
    cosfont === CosNull && return glyph_name_to_cid, cid_to_glyph_name
    subtype = get(cosfont, cn"Subtype")
    subtype === cn"Type0" && return glyph_name_to_cid, cid_to_glyph_name

    update_glyph_id_std_14(cosfont, glyph_name_to_cid, cid_to_glyph_name) &&
        return glyph_name_to_cid, cid_to_glyph_name

    encoding = cosDocGetObject(cosdoc, cosfont, cn"Encoding")
    encoding === CosNull && return glyph_name_to_cid, cid_to_glyph_name
    
    baseenc = typeof(encoding) === CosName ? encoding :
        cosDocGetObject(cosdoc, encoding, cn"BaseEncoding")
    gn2cid, cid2gn =
        baseenc == cn"WinAnsiEncoding"   ?
        (GlyphName_to_WINEncoding, WINEncoding_to_GlyphName) :
        baseenc == cn"MacRomanEncoding"  ?
        (GlyphName_to_MACEncoding, MACEncoding_to_GlyphName) :
        baseenc == cn"MacExpertEncoding" ?
        (Glyphname_to_MEXEncoding, MEXEncoding_to_GlyphName) :
        (GlyphName_to_STDEncoding, STDEncoding_to_GlyphName)

    if subtype !== cn"Type3"
        merge!(glyph_name_to_cid, gn2cid)
        merge!(cid_to_glyph_name, cid2gn)
    end
    typeof(encoding) === CosName && return glyph_name_to_cid, cid_to_glyph_name
    diff = cosDocGetObject(cosdoc, encoding, cn"Differences")
    diff === CosNull && return glyph_name_to_cid, cid_to_glyph_name
    values = get(diff)
    d = Dict()
    cid = -1
    for v in values
        if v isa CosInt
            cid = get(v)
        else
            @assert cid != -1
            glyph_name_to_cid[v] = cid
            cid_to_glyph_name[cid] = v
            cid += 1
        end
    end
    return glyph_name_to_cid, cid_to_glyph_name
end

get_encoded_string(s::CosString, fum::Nothing) = CDTextString(s)

get_encoded_string(s::CosString, fum::FontUnicodeMapping) = 
    get_encoded_string(Vector{UInt8}(s), fum)

@inline function get_encoded_string(v::Vector{UInt8}, fum::FontUnicodeMapping)
    length(v) == 0 && return ""
    fum.hasCMap && return get_encoded_string(v, fum.cmap)
    return String(NativeEncodingToUnicode(v, fum.encoding))
end

function get_unicode_chars(b::UInt8, i::Interval, v::Union{CosXString, CosArray})
    f = i.lo
    l = i.hi
    if v isa CosXString
        bytes = Vector{UInt8}(v)
        carr = get_unicode_chars(bytes)
        carr[1] += (b - f)  # Only one char should be generated here
    elseif v isa CosArray
        @assert v isa CosArray
        arr = get(v)
        xstr = arr[b - f + 1]
        @assert xstr isa CosXString
        bytes = Vector{UInt8}(xstr)
        carr = get_unicode_chars(bytes)
    end
    return carr
end

function get_unicode_chars(barr::Vector{UInt8})
    l = length(barr)
    nb = 0
    retarr = Vector{Char}()
    while nb < l
        b1 = barr[1]
        b2 = barr[2]
        nb += 2
        c::UInt32 = 0
        if 0xD8  <= b1 <= 0xDB
            # UTF-16 Supplementary plane = 4 bytes
            b1 -= 0xD8
            c = b1
            c = (c << 8) + b2
            b3 = barr[3]
            b4 = barr[4]
            nb += 2
            if 0xDC <= b3 <= 0xDF
                b3 -= 0xDC
                c1 = b3
                c1 = (c1 << 8) + b4
                c = (c << 10) + c1
                c += 0x10000
            end
        else
            c = b1
            c = (c << 8) + b2
        end
        push!(retarr, Char(c))
    end
    return retarr
end

get_encoded_string(s::CosString, cmap::CMap) =
    get_encoded_string(Vector{UInt8}(s), cmap::CMap)

function get_encoded_string(barr::Vector{UInt8}, cmap::CMap)
    cs = cmap.code_space
    rm = cmap.range_map
    l = length(barr)
    b1 = b2 = 0x0
    carr = Vector{Char}()
    retarr = Vector{Char}()
    i = 0
    while i < l
        b1 = barr[i+=1]
        xs = intersect(cs, Interval(b1, b1))
        # When byte range is not in code space we should not return NUL.
        if length(xs) == 0
            push!(carr, Char(0))
            continue
        end
        # Some cmaps do not call out single byte ranges explicitly in the
        # code space. So may need to decipher the existence of a single
        # byte vs 2-byte code from the range map. See `else` below.
        itree = xs[1][2]
        # This case is very clearly a single byte range 
        if itree === CosNull 
            itv = intersect(rm, Interval(b1, b1))
            if length(itv) > 0
                carr = get_unicode_chars(b1, itv[1][1], itv[1][2])
            else
                push!(carr, Char(0))
            end
        else
            itree1 = intersect(rm, Interval(b1, b1))
            if length(itree1) == 0
                push!(carr, Char(0))
                continue
            end
            # This is a single byte range case
            if itree1[1][2] isa CosObject
                carr = get_unicode_chars(b1, itree1[1][1], itree1[1][2])
            else
                b2 = barr[i+=1]
                itv = intersect(itree1[1][2], Interval(b2, b2))
                if length(itv) > 0
                    carr = get_unicode_chars(b2, itv[1][1], itv[1][2])
                else
                    push!(carr, Char(0))
                end
            end
        end
        append!(retarr, carr)
    end
    return retarr
end

cmap_command(b::Vector{UInt8}) = 
    b != beginbfchar && b != beginbfrange && b != begincodespacerange ?
        nothing : Symbol(String(b))

function on_cmap_command!(stm::IO, command::Symbol,
                         params::Vector{CosInt}, cmap::CMap)
    n = get(pop!(params))
    o1, o2, o3 = CosNull, CosNull, CosNull
    for i = 1:n
        o1 = parse_value(stm)
        @assert isa(o1, CosXString)
        d1 = Vector{UInt8}(o1)
        o2 = (command == :beginbfchar) ? o1 : parse_value(stm)
        @assert isa(o2, CosXString)
        d2 = Vector{UInt8}(o2)
        if (command != :begincodespacerange)
            o3 = parse_value(stm)
            @assert isa(o3, CosXString) || isa(o3, CosArray)
            l = length(d1)
            if l == 1
                cmap.range_map[Interval(d1[1], d2[1])] = o3
            else
                imap = get!(cmap.range_map, Interval(d1[1], d2[1]),
                            IntervalTree{UInt8, CosObject}())
                imap[Interval(d1[2], d2[2])] = o3
            end
        else
            l = length(d1)
            if l == 1
                cmap.code_space[Interval(d1[1], d2[1])] = CosNull
            else
                imap = IntervalTree{UInt8, CosNullType}()
                imap[Interval(d1[2], d2[2])] = CosNull
                cmap.code_space[Interval(d1[1], d2[1])] = imap
            end
        end
    end
    return cmap
end

on_cmap_command!(stm::IO, command::CosObject,
                 params::Vector{CosInt}, cmap::CMap) = nothing

function read_cmap(stm::IO)
    tcmap = CMap()
    params = Vector{CosInt}()
    while !eof(stm)
        obj = parse_value(stm, cmap_command)
        if isa(obj, CosInt)
            push!(params, obj)
        end
        (obj == :beginbfchar || obj == :beginbfrange ||
         obj == :begincodespacerange) &&
            on_cmap_command!(stm, obj, params, tcmap)
    end
    return tcmap
end

struct CIDWidth
    imap::IntervalTree{UInt16, Int}
    dw::Int
    CIDWidth(m::IntervalTree{UInt16, Int}, tdw::Int) = new(m, tdw)
end

CIDWidth(m::IntervalTree{UInt16, Int}) = CIDWidth(m, 1000)
CIDWidth(tdw::Int) = CIDWidth(IntervalTree{UInt16, Int}(), tdw)
CIDWidth() = CIDWidth(1000)

mutable struct PDFont
    doc::PDDoc
    obj::IDD{CosDict}
    widths::Union{AdobeFontMetrics, Vector{Float32}, CIDWidth}
    fum::FontUnicodeMapping
    glyph_name_to_cid::Dict{CosName, UInt8}
    cid_to_glyph_name::Dict{UInt8, CosName}
    flags::UInt32
    fontname::CosName
    @inline function PDFont(doc::PDDoc, cosfont::IDD{CosDict})
        fum = FontUnicodeMapping()
        merge_encoding!(fum, doc.cosDoc, cosfont)
        widths = get_font_widths(doc.cosDoc, cosfont)
        glyph_name_to_cid, cid_to_glyph_name =
            get_glyph_id_mapping(doc.cosDoc, cosfont)
        flags = get_font_flags(doc, cosfont, widths)
        fontname = get_font_name(doc, cosfont, widths)
        return new(doc, cosfont, widths, fum, glyph_name_to_cid,
                   cid_to_glyph_name, flags, fontname)
    end
end

INIT_CODE(::CIDWidth) = 0x0000
SPACE_CODE(w::CIDWidth) = get_character_code(cn"space", w)
INIT_CODE(x) = 0x00
SPACE_CODE(x) = get_character_code(cn"space", x)

pdFontIsBold(pdfont::PDFont)     = (pdfont.flags & 0x80000000) > 0
pdFontIsItalic(pdfont::PDFont)   = (pdfont.flags & 0x00000040) > 0
pdFontIsFixedW(pdfont::PDFont)   = (pdfont.flags & 0x00000001) > 0
pdFontIsAllCap(pdfont::PDFont)   = (pdfont.flags & 0x00010000) > 0
pdFontIsSmallCap(pdfont::PDFont) = (pdfont.flags & 0x00020000) > 0

# Not supported FD attribute in CIDFonts
@inline function get_font_flags(doc::PDDoc, cosfont::IDD{CosDict}, widths)
    flags = 0x00000000
    refdesc = get(cosfont, cn"FontDescriptor")
    refdesc === CosNull && return get_font_flags(widths)
    cosflags = cosDocGetObject(doc.cosDoc, refdesc, cn"Flags")
    cfweight = cosDocGetObject(doc.cosDoc, refdesc, cn"FontWeight")
    cfname   = cosDocGetObject(doc.cosDoc, refdesc, cn"FontName")
    cfweight !== CosNull && get(cfweight) >= 700 && (flags |= 0x80000000)
    cfname   !== CosNull &&
        (occursin("Bold", string(cfname)) ||
         occursin("bold", string(cfname))) &&
        (flags |= 0x80000000)
    cosflags !== CosNull && (flags += UInt32(get(cosflags)))
    return flags
end
get_font_flags(x) = 0x00000000

@inline function get_font_name(doc::PDDoc, cosfont::IDD{CosDict}, widths)
    refdesc = get(cosfont, cn"FontDescriptor")
    refdesc === CosNull && return get_font_name(cosfont, widths)    
    return cosDocGetObject(doc.cosDoc, refdesc, cn"FontName")
end
#Not implemented for CIDFonts
get_font_name(cosfont::IDD{CosDict}, ::CIDWidth) = cn"" 
function get_font_name(cosfont::IDD{CosDict}, x)
    subtype   = get(cosfont, cn"Subtype")
    if subtype === cn"Type3"
        name = get(cosfont, cn"Name")
        name === CosNull && return cn"Type3"
        return name
    end
    basefname = get(cosfont, cn"BaseFont")
    basefname === CosNull &&
        error("Non-standard 14 fonts having no BaseFont")
    return basefname
end

function get_character_code(name::CosName, pdfont::PDFont)
    length(pdfont.glyph_name_to_cid) > 0 &&
        return get(pdfont.glyph_name_to_cid, name, INIT_CODE(pdfont.widths))
    return get_character_code(name, pdfont.widths)
end

get_character_code(name::CosName, w::CIDWidth) =
    UInt16(get(AGL_Glyph_to_Unicode, name, INIT_CODE(w)))

get_character_code(name::CosName, w) =
    get(GlyphName_to_STDEncoding, name, INIT_CODE(w))

get_encoded_string(s, pdfont::PDFont) = get_encoded_string(s, pdfont.fum)

get_char(barr, w) = iterate(barr)
function get_char(barr, w::CIDWidth)
    next = iterate(barr)
    next === nothing && return nothing
    (b1, state) = next
    next = iterate(barr, state)
    @assert next !== nothing "Error in obtaining character data"
    (b2, state) = next
    return (UInt16(b1*0x0100 + b2), state)
end

function get_char(barr, state, w::CIDWidth)
    next = iterate(barr, state)
    next === nothing && return nothing
    (b1, state) = next
    next = iterate(barr, state)
    @assert next !== nothing "Error in obtaining character data"
    (b2, state) = next
    return (UInt16(b1*0x0100 + b2), state)
end
get_char(barr, state, w) = iterate(barr, state)

function get_string_width(barr::Vector{UInt8}, widths, pc, tfs, tj, tc, tw)
    totalw = 0f0
    next = get_char(barr, widths)
    while next !== nothing
        c, st = next
        w = get_character_width(c, widths)
        kw = get_kern_width(pc, c, widths)
        w = (w - tj)*tfs / 1000f0 + ((c == SPACE_CODE(widths)) ? tw : tc)
        w += kw
        pc = c
        tj = 0f0
        totalw += w
        next = get_char(barr, st, widths)
    end
    return totalw
end

function get_TextBox(ss::Vector{Union{CosString,CosNumeric}},
                     pdfont::PDFont,
                     tfs, tc, tw, th)
    totalw = 0f0
    tj = 0f0
    text = ""
    for s in ss
        if s isa CosString
            prev_char = INIT_CODE(pdfont.widths)
            t = String(get_encoded_string(s, pdfont))
            if (-tj) > 180 && length(t) > 0 && t[1] != ' ' &&
                length(text) > 0 && text[end] != ' '
                text *= " "
            end
            text *= t
            barr = Vector{UInt8}(s)
            totalw += get_string_width(barr, pdfont.widths, prev_char,
                                       tfs, tj, tc, tw)
            tj = 0f0
        elseif s isa CosNumeric
            tj = s |> get |> Float32
        end
    end
    totalw *= th
    return text, totalw, tfs
end

function get_character_width(cid::UInt16, w::CIDWidth)
    itv = intersect(w.imap, Interval(cid, cid))
    length(itv) == 0 && return w.dw
    return itv[1][2]
end
