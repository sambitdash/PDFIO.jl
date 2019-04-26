---
title: 'PDFIO: PDF Reader Library for native Julia'
tags:
  - Julia
  - PDF
  - document archive
  - data extraction
  - text extraction
  - data mining
  - data management
authors:
  - name: Sambit Kumar Dash
    orcid: 0000-0003-4856-7244
    affiliation: "1"
affiliations:
 - name: Director, Lenatics Solutions Pvt. Ltd.
   index: 1
date: 26 April 2019
bibliography: paper.bib
---

# Summary

Portable Document Format (PDF) is the most ubiquitous file format today for text,
scientific research, legal documentation and many other domains for information
dissemination and presentation. A large body of text is currently available as
archive in this format as well. Julia is an upcoming programming language in the
field of data sciences with focus on text analysis. Extracting archived content 
to text extracted form is highly beneficial to the language usage and adoption. 

``PDFIO`` is an API developed purely in Julia. Almost, all the functionality of 
PDF understanding is entirely written from scratch in Julia with only exception 
of usage of certain (de)compression codecs where standard open source softwares 
are being used. The API is written keeping the low level understanding of the PDF
specification. This enables these APIs to be used in real life data science 
applications where higher level knowledge abstractions can be built over the low
level libraries. However, an understanding of PDF specification(PDF-32000-1:2008)[@Adobe:2008]
may be needed to accomplish certain advanced tasks with the APIs. 

The APIs are developed for text extraction as a major focus. The rendering and 
printing aspects of PDF are not provided enough consideration. Secondly, a native 
script based language was chosen as PDF specification is highly misunderstood 
and interpretations significantly vary from document creator to creator. A script
based language provides flexibility to fix issues as we discover more nuances in
the new files we discover. Thirdly, every well-developed native library out in 
the market need connectors and PDF being a standard should have native support in
a modern language. Although, one can claim PDF is not the most ideal language for
text processing, it's just ubiquitous and cannot be ignored.

# Acknowledgements

We acknowledge contributions of all the community developers who have 
contributed to this effort. Their contribution can be viewed from the following
[link](https://github.com/sambitdash/PDFIO.jl/graphs/contributors).

# References
