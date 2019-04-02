function make_number(data, start, nbytes)
    sum = 0
    for ii = 1:nbytes
        sum *= 256
        sum += data[start+ii]
    end
    return sum
end

function get_xref_record(data, start, w)
    v=Vector{Int}()
    for tw in w
        n = make_number(data, start, tw)
        start += tw
        push!(v, n)
    end
    return v
end

function createObjectStreams(stm::CosStream)
    objtype = get(stm, cn"Type")
    objtype == cn"ObjStm" && return CosObjectStream(stm)
    return stm
end

function read_xref_stream(xrefstm::IDD{CosStream},
                          xref::Dict{CosIndirectObjectRef, CosObjectLoc})

    @assert get(xrefstm, cn"Type") == cn"XRef"
    size = get(xrefstm, cn"Size")
    @assert size !=CosNull

    w = get(xrefstm, cn"W")
    @assert w != CosNull
    @assert length(w) == 3

    index = get(xrefstm, cn"Index")

    if (index == CosNull)
        index = CosArray([CosInt(0),size])
    end

    # The xref stream may be accessed later. There is no point encrypting this data
    # Ideal will be to remove the filter.
    cosStreamRemoveFilters(xrefstm)

    input = get(xrefstm)
    data = read(input)
    util_close(input)
    datasize = length(data)

    w_n = get(w,true) #This size is 3
    recsize = sum(w_n)

    lenidx = length(index)
    @assert rem(lenidx,2) == 0
    idx_int=get(index,true)

    it = 0 #iterator for data
    for i = 1:div(lenidx,2)
        for j = 0:idx_int[2*i] - 1
            oid = idx_int[2*i-1]+j
            record = get_xref_record(data, it, w_n)
            @assert length(record) == 3
            @assert record[1] in 0:2

            loc = (record[1] == 1) ? record[2] :
                  (record[1] == 2) ? record[3] : 0
            stm = (record[1] == 2) ? CosIndirectObjectRef(record[2],0) : CosNull
            ref = (record[1] == 1) ? CosIndirectObjectRef(oid, record[3]) :
                  (record[1] == 2) ? CosIndirectObjectRef(oid, 0) :
                                     CosIndirectObjectRef(0,0)
            it += recsize
            record[1] != 0 && !haskey(xref,ref) && (xref[ref] = CosObjectLoc(loc,stm))
            it >= datasize && break
        end
        it >= datasize && break
    end
    return xref
end

function read_object_info_from_stm(stm::CosStream,
                                   oids::Vector{Int},
                                   oloc::Vector{Int},
                                   n::Int, first::Int)
    filename = get(stm, CosName("F"))
    io = util_open(String(filename),"r")
    try
        for i = 1:n
            oids[i] = convert(Int, parse_unsignednumber(io))
            oloc[i] = convert(Int, parse_unsignednumber(io)) + first
        end
    finally
        util_close(io)
    end
end

cosObjectStreamGetObject(stm::CosIndirectObject{CosObjectStream},
                         ref::CosIndirectObjectRef, loc::Int) =
                             cosObjectStreamGetObject(stm.obj, ref, loc)

function cosObjectStreamGetObject(stm::CosObjectStream,
                                  ref::CosIndirectObjectRef,
                                  loc::Int)
    objtuple = get(ref)
    stm.oids[loc+1] != objtuple[1] && return CosNull
    dirobj = cosObjectStreamGetObject(stm, CosNull, loc)
    return CosIndirectObject(objtuple[1], objtuple[2], dirobj)
end

function cosObjectStreamGetObject(stm::CosObjectStream,
                                  ref::CosNullType,
                                  loc::Int)
    filename = get(stm, cn"F")
    io = util_open(String(filename),"r")
    ps = io
    try
        seek(ps, stm.oloc[loc+1])
        obj = parse_value(ps)
        return obj
    finally
        util_close(ps)
    end
end
