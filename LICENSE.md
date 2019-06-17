# PDFIO License 

The PDFIO.jl package is licensed under the MIT "Expat" License:

> Copyright (c) 2017-2019: Sambit Kumar Dash.
> 
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
> 
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
> 
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.
> 
PDFIO is dependent on packages like `AbstractTrees`, `AdobeGlyphList`, 
`Documenter`, `LabelNumerals`, `Rectangle`, `RomanNumerals`, `WinRPM`, `ZipFile` 
that use similar licenses. 

## LZW Decompression

The author has provided an own implementation of the LZW decompression
clearly believing the older patents are no longer in force. Excerpts from
reference article from [GNU Website](https://www.gnu.org/philosophy/gif.html)
provided here for reference:

> There is no special patent threat to GIF format nowadays as far as we know; 
> the patents that were used to attack GIF have expired. Nonetheless, this 
> article will remain pertinent as long as programs can be forbidden by patents,
> since the same sorts of things could happen in any area of computing. See our 
> web site policies regarding GIFs, and our web guidelines.
>
>
> ...
>
>
> We were able to search the patent databases of the USA, Canada, Japan, and
> the European Union. The Unisys patent expired on 20 June 2003 in the USA, 
> in Europe it expired on 18 June 2004, in Japan the patent expired on 20 June
> 2004 and in Canada it expired on 7 July 2004. The U.S. IBM patent expired 11
> August 2006. The Software Freedom Law Center says that after 1 October 2006,
> there will be no significant patent claims interfering with the use of static
> GIFs.
> 
> Animated GIFs are a different story. We do not know what patents might cover 
> them. However, we have not heard reports of threats against use of animated 
> GIFs. Any software can be threatened by patents, but we have no reason to 
> consider animated GIFs to be in particular danger — no particular reason to 
> shun them.


# Licenses of third party libraries or data

## OpenSSL

OpenSSL is licensed under Apache License 2.0. The detailed license can be found
at: [https://github.com/openssl/openssl/blob/master/LICENSE](https://github.com/openssl/openssl/blob/master/LICENSE)

## Zlib

The software links with `Zlib` library for certain decompression modules. The
license for the same can be found at: https://www.zlib.net/zlib_license.html

Also stated here for reference:

>/* zlib.h -- interface of the 'zlib' general purpose compression library
>  version 1.2.11, January 15th, 2017
>
>  Copyright (C) 1995-2017 Jean-loup Gailly and Mark Adler
>
>  This software is provided 'as-is', without any express or implied
>  warranty.  In no event will the authors be held liable for any damages
>  arising from the use of this software.
>
>  Permission is granted to anyone to use this software for any purpose,
>  including commercial applications, and to alter it and redistribute it
>  freely, subject to the following restrictions:
>
>  1. The origin of this software must not be misrepresented; you must not
>     claim that you wrote the original software. If you use this software
>     in a product, an acknowledgment in the product documentation would be
>     appreciated but is not required.
>  2. Altered source versions must be plainly marked as such, and must not be
>     misrepresented as being the original software.
>  3. This notice may not be removed or altered from any source distribution.
>
>  Jean-loup Gailly        Mark Adler
>  jloup@gzip.org          madler@alumni.caltech.edu
>
> */

## Adobe Font Metrics

The software utilizes `Adobe Fonts Metrics` data files which are included under
the following license terms:

> This file and the 14 PostScript(R) AFM files it accompanies may be used, 
> copied, and distributed for any purpose and without charge, with or without 
> modification, provided that all copyright notices are retained; that the AFM 
> files are not distributed without this file; that all modifications to this 
> file or any of the AFM files are prominently noted in the modified file(s); 
> and that this paragraph is not modified. Adobe Systems has no responsibility 
> or obligation to support the use of the AFM files.

## Adobe Glyph List

The software utilizes `Adobe Glyph List (AGL & AGL-FN)` glyph codes that can be
used under the following license terms:

> Copyright 2002, 2010, 2015 Adobe Systems Incorporated.
> All rights reserved.
>
> Redistribution and use in source and binary forms, with or without
> modification, are permitted provided that the following conditions are
> met:
> 
> Redistributions of source code must retain the above copyright notice,
> this list of conditions and the following disclaimer.
>
> Redistributions in binary form must reproduce the above copyright
> notice, this list of conditions and the following disclaimer in the
> documentation and/or other materials provided with the distribution.
> 
> Neither the name of Adobe Systems Incorporated nor the names of its
> contributors may be used to endorse or promote products derived from
> this software without specific prior written permission.

> THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
> "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
> LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
> A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
> HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
> SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
> LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
> DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
> THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
> (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
> OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
