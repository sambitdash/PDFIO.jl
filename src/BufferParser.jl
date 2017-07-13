using BufferedStreams

export skipv,
       advance!,
       locate_keyword!,
       chomp_space!,
       chomp_eol!

@inline function chomp_space!(ps::BufferedInputStream)
    while !eof(ps) && ispdfspace(peek(ps))
      skip(ps,1)
    end
end

@inline function chomp_eol!(ps::BufferedInputStream)
    @inbounds while !eof(ps) && is_crorlf(peek(ps))
        skip(ps,1)
    end
end

function skipv(ps::BufferedInputStream, c::UInt8)
    if peek(ps) == c
        skip(ps,1)
    else
        error("Expected '$(Char(c))' here")
    end
end

function skipv(ps::BufferedInputStream, cs::UInt8...)
    for c in cs
        skipv(ps, c)
    end
end

function skipv(ps::BufferedInputStream, cs::Array{UInt8,1})
    for c in cs
        skipv(ps, c)
    end
end

@inline advance!(ps::BufferedInputStream)=read(ps,UInt8)

function kmp_preprocess(P)
    m = length(P)
    pi = Vector{Int}(m)
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

function locate_keyword!(ps::BufferedInputStream, keyword, maxoffset=length(keyword))
    m = length(keyword)
    pi = kmp_preprocess(keyword)

    q = 0
    found=false
    offset = 0
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
