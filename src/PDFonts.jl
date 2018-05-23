import ..Cos: CosXString

using Rectangle

#=
Sample CMaps are available now as 8.cmap and 16.cmap in the test/files directory for 8 and
16-bit toUnicode CMaps.

CMaps can have both 8 and 16 bit ranges in the same CMap file as well.
=#
const beginbfchar = b"beginbfchar"
const endbfchar   = b"endbfchar"
const beginbfrange = b"beginbfrange"
const endbfrange = b"endbfrange"
const begincodespacerange = b"begincodespacerange"
const endcodespacerange = b"endcodespacerange"


mutable struct CMap
    code_space::IntervalTree{UInt8, Union{CosNullType, IntervalTree{UInt8, CosNullType}}}
    range_map::IntervalTree{UInt8, Union{CosObject, IntervalTree{UInt8, CosObject}}}
    CMap() = new(IntervalTree{UInt8, Union{CosNullType, IntervalTree{UInt8, CosNullType}}}(),
        IntervalTree{UInt8, Union{CosObject, IntervalTree{UInt8, CosObject}}}())
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
                         doc::CosDoc, font::CosObject)
    encoding_mapping =  encoding == cn"WinAnsiEncoding"   ? WINEncoding_to_Unicode :
                        encoding == cn"MacRomanEncoding"  ? MACEncoding_to_Unicode :
                        encoding == cn"MacExpertEncoding" ? MEXEncoding_to_Unicode :
                        STDEncoding_to_Unicode
    merge!(fum.encoding, encoding_mapping)
    return fum
end

# for type 0 use cmap.
# for symbol and zapfdingbats - use font encoding
# for others use STD Encoding
# Reading encoding from the font files in case of Symbolic fonts are not supported.
# Font subset is addressed with font name identification.
function merge_encoding!(fum::FontUnicodeMapping, encoding::CosNullType,
                        doc::CosDoc, font::CosObject)
    subtype  = cosDocGetObject(doc, font, cn"Subtype")
    (subtype != cn"Type1") && (subtype != cn"MMType1") && return fum
    basefont = cosDocGetObject(doc, font, cn"BaseFont")
    basefont_with_subset = CDTextString(basefont)
    basefont_str = rsplit(basefont_with_subset, '+';limit=2)[end]
    enc = (basefont_str == "Symbol") ? SYMEncoding_to_Unicode :
          (basefont_str == "ZapfDingbats") ? ZAPEncoding_to_Unicode :
          STDEncoding_to_Unicode
    merge!(fum.encoding, enc)
    return fum
end

function merge_encoding!(fum::FontUnicodeMapping,
                        encoding::Union{CosDict, CosIndirectObject{CosDict}},
                        doc::CosDoc, font::CosObject)
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

function merge_encoding!(fum::FontUnicodeMapping, doc::CosDoc, font::CosObject)
    encoding = cosDocGetObject(doc, font, cn"Encoding")
    merge_encoding!(fum, encoding, doc, font)
    toUnicode = cosDocGetObject(doc, font, cn"ToUnicode")
    toUnicode == CosNull && return fum
    merge_encoding!(fum, toUnicode, doc, font)
end

function merge_encoding!(fum::FontUnicodeMapping, cmap::CosIndirectObject{CosStream},
                         doc::CosDoc, font::CosObject)
    stm_cmap = get(cmap)
    try
        fum.cmap = read_cmap(stm_cmap)
        fum.hasCMap = true
    finally
        close(stm_cmap)
    end
    return fum
end

function get_glyph_id_mapping(cosdoc::CosDoc, cosfont::CosObject)
    glyph_name_id = Dict{CosName, UInt8}()
    (cosfont === CosNull) && return glyph_name_id
    subtype = get(cosfont, cn"Subtype")
    (subtype === cn"Type0") && return glyph_name_id
    baseenc = cosDocGetObject(cosdoc, cosfont, cn"BaseEncoding")
    encoding_mapping =  baseenc == cn"WinAnsiEncoding"   ? GlyphName_to_WINEncoding :
                        baseenc == cn"MacRomanEncoding"  ? GlyphName_to_MACEncoding :
                        baseenc == cn"MacExpertEncoding" ? Glyphname_to_MEXEncoding :
                        GlyphName_to_STDEncoding
    merge!(glyph_name_id, encoding_mapping)

    diff = cosDocGetObject(cosdoc, cosfont, cn"Differences")
    diff === CosNull && return glyph_name_id
    values = get(diff)
    d = Dict()
    cid = -1
    for v in values
        if v isa CosInt
            cid = get(v)
        else
            @assert cid != -1
            glyph_name_id[v] = cid
            cid += 1
        end
    end
    return glyph_name_id
end

get_encoded_string(s::CosString, fum::Void) = CDTextString(s)

function get_encoded_string(s::CosString, fum::FontUnicodeMapping)
    v = Vector{UInt8}(s)
    length(v) == 0 && return ""
    fum.hasCMap && return get_encoded_string(s, fum.cmap)
    carr = NativeEncodingToUnicode(Vector{UInt8}(s), fum.encoding)
    return String(carr)
end

function get_unicode_chars(b::UInt8, i::Interval, v::CosObject)
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
    else
        @assert 1 == 0
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

function get_encoded_string(s::CosString, cmap::CMap)
    cs = cmap.code_space
    rm = cmap.range_map
    barr = Vector{UInt8}(s)
    l = length(barr)
    b1 = b2 = 0x0
    carr = Vector{Char}()
    retarr = Vector{Char}()
    i = 0
    while i < l
        b1 = barr[i+=1]
        xs = intersect(cs, Interval(b1, b1))
        length(xs) == 0 && continue
        itree = xs[1][2]
        if itree === CosNull
            itv = intersect(rm, Interval(b1, b1))
            if length(itv) > 0
                carr = get_unicode_chars(b1, itv[1][1], itv[1][2])
            else
                push!(carr, Char(0))
            end
        else
            b2 = barr[i+=1]
            itree1 = rm[Interval(b1, b1)] # CMaps do not have ranges on 1st byte
            itv = intersect(itree1, Interval(b2, b2))
            if length(itv) > 0
                carr = get_unicode_chars(b2, itv[1][1], itv[1][2])
            else
                push!(carr, Char(0))
            end
        end
        append!(retarr, carr)
    end
    return retarr
end

function cmap_command(b::Vector{UInt8})
    b != beginbfchar && b != beginbfrange && b != begincodespacerange && return nothing
    return Symbol(String(b))
end

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
        (obj == :beginbfchar || obj == :beginbfrange || obj == :begincodespacerange) &&
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
    obj::CosObject
    widths::Union{AdobeFontMetrics, Vector{Int}, CIDWidth}
    fum::FontUnicodeMapping
    glyph_name_id::Dict{CosName, UInt8}
end

INIT_CODE(::CIDWidth) = 0x0000
SPACE_CODE(w::CIDWidth) = get_character_code(cn"space", w)
INIT_CODE(x) = 0x00
SPACE_CODE(x) = get_character_code(cn"space", x)

function get_character_code(name::CosName, pdfont::PDFont)
    length(pdfont.glyph_name_id) > 0 &&
        return get(pdfont.glyph_name_id, name, INIT_CODE(pdfont.widths))
    return get_character_code(name, pdfont.widths)
end

get_character_code(name::CosName, w::CIDWidth) =
    UInt16(get(AGL_Glyph_to_Unicode, name, INIT_CODE(w)))

get_character_code(name::CosName, w) =
    get(GlyphName_to_STDEncoding, name, INIT_CODE(w))

get_encoded_string(s, pdfont::PDFont) = get_encoded_string(s, pdfont.fum)

function get_char(barr, state, w::CIDWidth)
    (b1, state) = next(barr, state)
    (b2, state) = next(barr, state)
    return (b1*0x0100 + b2, state)
end
get_char(barr, state, w) = next(barr, state)

function get_string_width(barr::Vector{UInt8}, widths, pc, tfs, tj, tc, tw)
    totalw = 0.0
    st = start(barr)
    while !done(barr, st)
        c, st = get_char(barr, st, widths)
        w = get_character_width(c, widths)
        kw = get_kern_width(pc, c, widths)
        w = (w - tj)*tfs / 1000.0 + ((c == SPACE_CODE(widths)) ? tw : tc)
        w += kw
        pc = c
        tj = 0.0
        totalw += w
    end
    return totalw
end

function get_TextBox(ss::Vector{Union{CosString,CosNumeric}},
    pdfont::PDFont, tfs, tc, tw, th)
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
            totalw += get_string_width(barr, pdfont.widths, prev_char, tfs, tj, tc, tw)
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
