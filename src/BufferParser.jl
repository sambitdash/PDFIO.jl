export  skipv,
        advance!,
        locate_keyword!,
        chomp_space!,
chomp_eol!,
_peekb

import Base: peek

@inline function chomp_space!(ps::IO)
    n = 0
    while !eof(ps) && ps |> _peekb |> ispdfspace
        skip(ps, 1)
        n += 1
    end
    return n
end

@inline chomp_eol!(ps::IO) =
    while !eof(ps) && ps |> _peekb |> is_crorlf skip(ps,1) end

@inline function skipv(ps::IO, c::UInt8)
    ch = 0xff
    !eof(ps) && ((ch = ps |> _peekb) == c) && return skip(ps, 1)
    error("Found '$(Char(ch))($(UInt(ch)))' Expected '$(Char(c))' here")
end

_peekb(io::IO) = UInt8(peek(io))

@inline skipv(ps::IO, cs::Vector{UInt8}) = for c in cs skipv(ps, c) end

@inline advance!(ps::IO) = read(ps, UInt8)

function kmp_preprocess(P)
    m = length(P)
    pi = zeros(Int, m)
    pi[1] = 0
    k = 0
    for q = 2:m
        while k > 0 && P[k+1] != P[q]
            k = pi[k]
        end
        if P[k+1] == P[q]
            k += 1
        end
        pi[q] = k
    end
    return pi
end

# This cannot be called on a marked stream.
function locate_keyword!(ps::IO, keyword, maxoffset=length(keyword))
    m = length(keyword)
    pi = kmp_preprocess(keyword)

    q = 0
    found=false
    offset = 0
    @assert !ismarked(ps)
    mark(ps)
    while(true)
        c = advance!(ps)
        offset += 1
        while q > 0 && keyword[q+1] != c
            q = pi[q]
        end
        if keyword[q+1] == c
            q +=1
        end
        if q == m
            found = true
            q = pi[q]
            break
        end
        if (offset >= maxoffset)
            break
        end
    end
    if found
        unmark(ps)
        return (offset - length(keyword))
    else
        reset(ps)
        peek(ps)
        return -1
    end
end
