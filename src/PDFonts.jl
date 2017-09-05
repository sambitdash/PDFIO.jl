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

Single byte ToUnicode CMap

/CIDInit /ProcSet findresource begin 12 dict begin begincmap /CIDSystemInfo <<
/Registry (F15+0) /Ordering (T1UV) /Supplement 0 >> def
/CMapName /F15+0 def
/CMapType 2 def
1 begincodespacerange <01> <c9> endcodespacerange
18 beginbfchar
<05> <260E>
<0a> <261B>
<0b> <261E>
<20> <0020>
<29> <2605>
<4d> <25CF>
<4e> <274D>
<4f> <25A0>
<54> <25B2>
<55> <25BC>
<56> <25C6>
<57> <2756>
<58> <25D7>
<75> <2663>
<76> <2666>
<77> <2665>
<78> <2660>
<a2> <2192>
endbfchar
15 beginbfrange
<01> <04> <2701>
<06> <09> <2706>
<0c> <1f> <270C>
<21> <28> <2720>
<2a> <4c> <2729>
<50> <53> <274F>
<59> <5f> <2758>
<60> <6d> <F8D7>
<6e> <74> <2761>
<79> <82> <2460>
<83> <a1> <2776>
<a3> <a4> <2194>
<a5> <a7> <2798>
<a8> <bb> <279C>
<bc> <c9> <27B1>
endbfrange
endcmap CMapName currentdict /CMap defineresource pop end end

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
