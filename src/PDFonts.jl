import ..Cos: CosXString

using IntervalTrees

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
    code_space::IntervalMap{UInt8, Union{CosNullType, IntervalMap{UInt8, CosNullType}}}
    range_map::IntervalMap{UInt8, Union{CosObject, IntervalMap{UInt8, CosObject}}}
    CMap() = new(IntervalMap{UInt8, Union{CosNullType, IntervalMap{UInt8, CosNullType}}}(),
        IntervalMap{UInt8, Union{CosObject, IntervalMap{UInt8, CosObject}}}())
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
    baseenc !==  CosNull && merge_encoding!(fum, baseenc, doc, font)
    # Add the Differences
    diff = cosDocGetObject(doc, encoding, cn"Differences")
    diff === CosNull && return fum
    values = get(diff)
    d = Dict()
    cid = 0
    for v in values
        if v isa CosInt
            cid = get(v)
        else
            @assert cid != 0
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

get_encoded_string(s::CosString, fum::Void) = CDTextString(s)

function get_encoded_string(s::CosString, fum::FontUnicodeMapping)
    v = Vector{UInt8}(s)
    length(v) == 0 && return ""
    fum.hasCMap && return get_encoded_string(s, fum.cmap)
    carr = NativeEncodingToUnicode(Vector{UInt8}(s), fum.encoding)
    return String(carr)
end

function get_unicode_chars(b::UInt8, itv::IntervalValue)
    f = first(itv)
    l = last(itv)
    v = value(itv)
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

# Placeholder only
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
        if hasintersection(cs, b1)
            itree = value(collect(intersect(cs, (b1,b1)))[1])
            if itree === CosNull
                itv = collect(intersect(rm, (b1,b1)))[1]
                carr = get_unicode_chars(b1, itv)
            else
                b2 = barr[i+=1]
                itree1 = value(collect(intersect(rm, (b1,b1)))[1])
                itv = collect(intersect(itree1, (b2,b2)))
                if length(itv) > 0
                    carr = get_unicode_chars(b2, itv[1])
                else
                    push!(carr, Char(0))
                end
            end
            append!(retarr, carr)
        end
    end
    return retarr
end

function cmap_command(b::Vector{UInt8})
    b != beginbfchar && b != beginbfrange && b != begincodespacerange && return nothing
    return Symbol(String(b))
end

function on_cmap_command!(stm::BufferedInputStream, command::Symbol,
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
                cmap.range_map[(d1[1],d2[1])] = o3
            else
                if hasintersection(cmap.range_map, d1[1])
                    imap = value(collect(intersect(cmap.range_map, (d1[1], d2[1])))[1])
                else
                    imap = IntervalMap{UInt8, CosObject}()
                    cmap.range_map[(d1[1],d2[1])] = imap
                end
                imap[(d1[2], d2[2])] = o3
            end
        else
            l = length(d1)
            if l == 1
                cmap.code_space[(d1[1],d2[1])] = CosNull
            else
                imap = IntervalMap{UInt8, CosNullType}()
                imap[(d1[2], d2[2])] = CosNull
                cmap.code_space[(d1[1],d2[1])] = imap
            end
        end
    end
    return cmap
end

on_cmap_command!(stm::BufferedInputStream, command::CosObject,
                params::Vector{CosInt}, cmap::CMap) = nothing

function read_cmap(stm::BufferedInputStream)
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
