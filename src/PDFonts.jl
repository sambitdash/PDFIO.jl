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
          (basefont_str == "ZapfDigbats") ? ZAPEncoding_to_Unicode :
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
#    toUnicode = cosDocGetObject(doc, font, cn"ToUnicode")
#    toUnicode == CosNull && return fum
#    merge_encoding!(fum, toUnicode, doc, font)
end

function merge_encoding!(fum::FontUnicodeMapping, cmap::CosIndirectObject{CosStream},
                         doc::CosDoc, font::CosObject)
    fum.toUnicode = read_cmap(get(cmap))
    return fum
end

get_encoded_string(s::CosString, fum::Void) = CDTextString(s)

function get_encoded_string(s::CosString, fum::FontUnicodeMapping)
    fum.hasCMap && return get_encoded_string(s, fum.cmap)
    carr = NativeEncodingToUnicode(Vector{UInt8}(s), fum.encoding)
    return String(carr)
end

# Placeholder only
get_encoded_string(s::CosString, cmap::CMap) = CDTextString(s)

function cmap_command(b::Vector{UInt8})
    b != beginbfchar && b != beginbfrange && b != begincodespacerange && return nothing
    return Symbol(String(b))
end

function on_cmap_command(stm::BufferedInputStream, command::Symbol,
                         params::Vector{CosInt}, cmap::CMap)
    n = get(pop!(params))
    println(n)
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
            println(d1)
            l = length(d1)
            if l == 1
                cmap.range_map[(d1[1],d2[1])] = o3
            else
                imap = IntervalMap{UInt8, CosObject}()
                imap[(d1[2], d2[2])] = o3
                cmap.range_map[(d1[1],d2[1])] = imap
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
end

on_cmap_command(stm::BufferedInputStream, command::CosObject,
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
            on_cmap_command(stm, obj, params, tcmap)
    end
    return tcmap
end

#=
function get_encoded_string(s::CosXString, cmap::CosObject)
    cmap_vec = read_cmap(cmap)
    hexbytes = get(s)
    data = hexbytes |> String |> hex2bytes

    cmap_len = length(cmap_vec)

    for i = 1:cmap_len
        nb = cmap_vec[i][1]
    end

    for b in data
        #if b in
    end
    state = start(cmap_vec)
    nbytes = []
    while !done(cmap_vec, state)
        (r, state) = next(cmap_vec, state)
        isa(r[2], CosInt) && push!(nbytes, Int(r[2]))
    end
    for r in cmap_vec
        if isa(r[1], CosInt)
    end
    i = 1
    len = length(data)
    retval = UInt16[]
    while i < len
        c = parse(UInt16, String(data[i:i+3]), 16)
        for r in cmap_range
            range = r[1]
            if c in range
                incr = c - range[1]
                v = r[2]
                if isa(v, CosXString)
                    data2 = get(v)
                    c2 = parse(UInt16, String(data2), 16)
                    c2 += incr
                    push!(retval, c2)
                elseif isa(v, CosArray)
                    data2 = get(v)[incr+1]
                    j = 1
                    while j < length(data2)
                        c2 = parse(UInt16, String(data2[j:j+3]), 16)
                        push!(retval, c2)
                        j += 4
                    end
                end
            end
        end
        i += 4
    end
end
=#
