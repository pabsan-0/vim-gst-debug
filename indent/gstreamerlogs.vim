vim9script

if exists("b:did_indent")
    finish
endif
b:did_indent = 1

# Get the column where filesrc:nr:func starts
var first_line = getline(1)
var pattern = '^\s*\d\+:\d\+:\d\+\.\d\+\s\+\d\+\s\+0x\x\+\s\+\S\+\s\+\S\+\s\+'
var col_idx = matchend(first_line, pattern)
if col_idx != -1
    b:gstreamerlogs_indent = col_idx
endif


def g:GstreamerLogIndent(): number
    # Indent if continuation line i.e. not timestamp
    var line = getline(v:lnum)

    if line =~# '^\s*\d\+:\d\+:\d\+\.\d\+'
        return 0
    endif

    return get(b:, 'gstreamerlogs_indent', shiftwidth())
enddef

# Generic intentation
setlocal indentexpr=g:GstreamerLogIndent()

# Line wrapping
setlocal wrap
setlocal breakindent
setlocal breakindentopt=shift:4
