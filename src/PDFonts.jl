import ..Cos: CosXString

using IntervalTrees

# This is a very crude method to read a CMap. Standards compliant CMap reader can be very
# involved. This is a quick and dirty way to extract the encoding information.
#= Sample ToUnicode C-Map

/CIDInit /ProcSet findresource begin
18 dict begin
begincmap
/CIDSystemInfo
<< /Registry (Adobe)
/Ordering (UCS)
/Supplement 0
>> def
/CMapName /Adobe-Identity-UCS def
/CMapType 2 def
1 begincodespacerange
<0000> <FFFF>
endcodespacerange
1 beginbfchar
<0003> <0020>
endbfchar
1 beginbfrange
<000B> <000C> <0028>
endbfrange
2 beginbfchar
<000F> <002C>
<0011> <002E>
endbfchar
3 beginbfrange
<0013> <001C> <0030>
<0024> <0027> <0041>
<0029> <002A> <0046>
endbfrange
1 beginbfchar
<002C> <0049>
endbfchar
2 beginbfrange
<0031> <0033> <004E>
<0035> <0037> <0052>
endbfrange
1 beginbfchar
<0039> <0056>
endbfchar
4 beginbfrange
<0044> <0053> <0061>
<0055> <005C> <0072>
<00B2> <00B2> [<2014>]
<00B3> <00B4> <201C>
endbfrange
1 beginbfchar
<00B6> <2019>
endbfchar
endcmap
CMapName currentdict /CMap defineresource pop
end
end
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

mutable struct PDFont
    encoding::Dict
    toUnicode::CMap
    PDFont() = new(Dict(), CMap())
end

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

function read_cmap(cmap::CosObject)
    cmap === CosNull && return CosNull
    tcmap = CMap()
    params = Vector{CosInt}()
    stm = get(cmap)
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

get_encoded_string(s, font::CosNullType, page) = CDTextString(s)

get_encoded_string(s, font, page::CosNullType) = CDTextString(s)

# Simply applying ISO_8859-1. Not correct actually encoding tables to be consulted.
# like: WinAnsiEncoding, MacRomanEncoding, MacExpertEncoding or PDFDocEncoding
get_encoded_string(s::CosString, encoding::CosName) = CDTextString(s)

# Differences should be specifically mapped.

get_encoded_string(s::CosString, encoding::CosDict) = CDTextString(s)

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
