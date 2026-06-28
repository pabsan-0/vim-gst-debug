vim9script

# FIXME GST_DEBUG parsing
# FIXME escape codes

# Because user may not be comfortable with switching buffer views
# b:buffer_single = get(g:, gst_debug_buffer_single, true)
g:gst_debug_debug = true
g:gst_debug_multiline_scan_len = 50

const s_level_map = {
      \ 'none': 0, 'ERROR': 1, 'WARN': 2, 'FIXME': 3,
      \ 'INFO': 4, 'DEBUG': 5, 'LOG': 6, 'TRACE': 7, 'MEMDUMP': 9,
      \ }

# Flat schema: Every physical token in the log is a primary column.
const s_schema = [
    {name: 'timestamp', parser: '\d\+:\d\+:\d\+\.\d\+', sep: '\s\+', },
    {name: 'pid',       parser: '\d\+',                 sep: '\s\+', },
    {name: 'thread',    parser: '0x\x\+',               sep: '\s\+', },
    {name: 'level',     parser: '[A-Z]\+',              sep: '\s\+', },
    {name: 'category',  parser: '\S\+',                 sep: '\s\+', },
    {name: 'file',      parser: '[^:]\+',               sep: ':',    },
    {name: 'lineno',    parser: '\d\+',                 sep: ':',    },
    {name: 'function',  parser: '[^:]\+',               sep: ':',    },
    {name: 'element',   parser: '\%(<[^>]\+>\)\=',      sep: '\s*',  },
    {name: 'message',   parser: '.*',                   sep: '',     }
]

# Derived schema: Expressions and combinations.
const s_derived_schema = {
    _levelnum: { parent: 'level', expr: (ctx) => s_level_map[ctx.level] },
    _fileline: { parent: 'file',  expr: (ctx) => ctx.file .. ':' .. ctx.lineno },
    _findexpr: { parent: 'file',  expr: (ctx) => ctx.timestamp .. '\s+' .. ctx.pid .. '\s+' .. ctx.thread}
}

# Yields a list of regexes to parse a line.
# Each regex captures 8 groups and packs the rest of the line in the 9th.
# This allows chained parsing to overcome Vim's 9 capture groups limitation.
def BuildRegexChain(): list<string>
    var regex_chain = []
    var current_regex = '^'
    var group_count = 0

    for field in s_schema
        # If we'd need a 9th capture group, capture the rest of the line
        # and initiate a new pattern
        if group_count == 8
            # Close the current pattern and append it to the output list
            current_regex ..= '\(.*\)'
            add(regex_chain, current_regex)

            # Initiate a new pattern
            current_regex = '^'
            group_count = 0
        endif

        current_regex ..= '\(' .. field.parser .. '\)' .. field.sep
        group_count += 1
    endfor

    # Add the ongoing pattern to the output list
    if current_regex != '^'
        add(regex_chain, current_regex)
    endif

    return regex_chain
enddef
const s_regex_chain: list<string> = BuildRegexChain()


###################################################
##  Parsing anf seeking
###################################################

def ParseLine(a_lnum: number = -1): list<any>
    const target_lnum = a_lnum == -1 ? line('.') : a_lnum

    # Outcomes
    var fields: dict<any> = {}
    var locs: dict<any> = {}

    # Helpers
    const original_line = getline(target_lnum)
    var to_parse = original_line
    var field_idx = 0
    var offset = 0

    # Base schema extraction
    for regex in s_regex_chain
        var matches = matchlist(to_parse, regex)
        if empty(matches)
            return [fields, locs, target_lnum]
        endif

        var remaining_fields = min([8, len(s_schema) - field_idx])
        for i in range(remaining_fields)
            var field_name = s_schema[field_idx].name
            var val = matches[i + 1]

            # Store the field value
            fields[field_name] = val

            # And its location if not null
            if val != ''
                var match_idx = stridx(original_line, val, offset)
                if match_idx >= 0
                    locs[field_name] = {line: target_lnum, col: match_idx + 1}
                    offset = match_idx + len(val)
                endif
            endif
            field_idx += 1
        endfor

        if len(s_regex_chain) > 1 && field_idx < len(s_schema)
            to_parse = matches[9]
        endif
    endfor

    # Derived Extraction
    for [new_field, rule] in items(s_derived_schema)
        fields[new_field] = rule.expr(fields)
        if has_key(locs, rule.parent)
            locs[new_field] = copy(locs[rule.parent])
        endif
    endfor

    return [fields, locs, target_lnum]
enddef


def ParseMultiLine(a_lnum: number = -1): list<any>
    const lnum_scan_start = a_lnum == -1 ? line('.') : a_lnum

    var fields: dict<any> = {}
    var locs: dict<any> = {}
    var line_log_start: number = -1

    # Upward scan: aims to find a schema-matching log line
    for line_offset in range(g:gst_debug_multiline_scan_len)
        var lnum = lnum_scan_start - line_offset
        if lnum <= 0
            break
        endif

        [fields, locs, line_log_start] = ParseLine(lnum)
        if !empty(fields) && !empty(locs)
            break
        endif
    endfor

    # Downward scan: if log line was found, append further lines to last field
    const eof_lnum = line('$')
    const last_field_name = s_schema[-1].name
    if !empty(fields)
        for line_offset in range(g:gst_debug_multiline_scan_len)
            var lnum = line_log_start + line_offset + 1

            if !empty(ParseLine(lnum)[0]) || lnum > eof_lnum
                break
            endif

            fields[last_field_name] ..= "\n" .. getline(lnum)
        endfor
    endif

    return [fields, locs, line_log_start]
enddef


def SeekFieldBuildRegex(target_field: string, target_value: string, inverse: bool = false): string
    var field_found = false
    var regex = '^'

    for field in s_schema
        if field.name == target_field
            field_found = true
            var target_value_safe = escape(target_value, '.\*$^~[]')

            if inverse
                regex ..= '\%(' .. target_value_safe .. '\)\@!' .. field.parser
            else
                regex ..= target_value_safe
            endif
            break
        else
            regex ..= field.parser .. field.sep
        endif
    endfor

    if !field_found
        echoerr "Unknown log field: " .. target_field
        return ""
    endif

    return regex
enddef

if g:gst_debug_debug == true
    command! DebugParseLine           echom ParseLine(-1)
    command! DebugParseMultiLine      echom ParseMultiLine(-1)
    command! DebugSeekFieldBuildRegex echom SeekFieldBuildRegex("category", "GST_INIT", 0)
endif

###################################################
## Navigation - Horizontal
###################################################

export def CursorToField(fieldname: string, visual_select: bool = false)
    var lnum_scan_start = line('.')

    var [fields, locs, lnum] = ParseMultiLine(lnum_scan_start)
    if empty(fields)
        return
    endif

    var original_line = getline(lnum)
    var current_offset = 0

    for field in s_schema
        var val = get(fields, field.name, '')
        if empty(val)
            continue
        endif

        var val_lines = split(val, '\n', true)
        var first_line_val = val_lines[0]

        var match_idx = stridx(original_line, first_line_val, current_offset)
        if match_idx >= 0
            if field.name == fieldname
                execute "normal! m`"

                if visual_select
                    execute "normal! \<Esc>"
                    cursor(lnum, match_idx + 1)
                    execute "normal! v"
                    if len(val_lines) > 1
                        var end_col = max([1, len(val_lines[-1])])
                        cursor(lnum + len(val_lines) - 1, end_col)
                    else
                        cursor(lnum, match_idx + len(first_line_val))
                    endif
                else
                    cursor(lnum, match_idx + 1)
                endif
                return
            endif
            current_offset = match_idx + len(first_line_val)
        endif
    endfor
enddef

nnoremap g1 <Cmd>call gst_debug#CursorToField('timestamp')<CR>
nnoremap g2 <Cmd>call gst_debug#CursorToField('pid')<CR>
nnoremap g3 <Cmd>call gst_debug#CursorToField('thread')<CR>
nnoremap g4 <Cmd>call gst_debug#CursorToField('level')<CR>
nnoremap g5 <Cmd>call gst_debug#CursorToField('category')<CR>
nnoremap g6 <Cmd>call gst_debug#CursorToField('file')<CR>
nnoremap g7 <Cmd>call gst_debug#CursorToField('lineno')<CR>
nnoremap g8 <Cmd>call gst_debug#CursorToField('function')<CR>
nnoremap g9 <Cmd>call gst_debug#CursorToField('element')<CR>
nnoremap g0 <Cmd>call gst_debug#CursorToField('message')<CR>

xnoremap g1 <Cmd>call gst_debug#CursorToField('timestamp', 1)<CR>
xnoremap g2 <Cmd>call gst_debug#CursorToField('pid',       1)<CR>
xnoremap g3 <Cmd>call gst_debug#CursorToField('thread',    1)<CR>
xnoremap g4 <Cmd>call gst_debug#CursorToField('level',     1)<CR>
xnoremap g5 <Cmd>call gst_debug#CursorToField('category',  1)<CR>
xnoremap g6 <Cmd>call gst_debug#CursorToField('file',      1)<CR>
xnoremap g7 <Cmd>call gst_debug#CursorToField('lineno',    1)<CR>
xnoremap g8 <Cmd>call gst_debug#CursorToField('function',  1)<CR>
xnoremap g9 <Cmd>call gst_debug#CursorToField('element',   1)<CR>
xnoremap g0 <Cmd>call gst_debug#CursorToField('message',   1)<CR>


# FIXME merge with similar functions
def GetFieldUnderCursor(): list<string>
    var cur_pos = getcurpos()
    var current_lnum = cur_pos[1]
    var current_col = cur_pos[2]

    var [fields, locs, lnum] = ParseMultiLine(current_lnum)
    if empty(fields)
        return ['', '']
    endif

    var target_field = ''
    var target_value = ''

    # If cursor is on a continuation line of a multiline block
    if current_lnum > lnum
        target_field = s_schema[-1].name
        target_value = get(fields, target_field, '')
    else
        var original_line = getline(lnum)
        var current_offset = 0
        var prev_field = ''
        var prev_val = ''

        for field in s_schema
            var val = get(fields, field.name, '')
            if empty(val) | continue | endif

            var first_line_val = split(val, '\n', true)[0]
            var match_idx = stridx(original_line, first_line_val, current_offset)

            if match_idx >= 0
                var start_col = match_idx + 1
                var end_col = start_col + len(first_line_val) - 1

                # Belongs to previous field's trailing space
                if current_col < start_col && prev_field != ''
                    target_field = prev_field
                    target_value = prev_val
                    break
                endif

                # Physically inside this field
                if current_col >= start_col && current_col <= end_col
                    target_field = field.name
                    target_value = val
                    break
                endif

                prev_field = field.name
                prev_val = val
                current_offset = match_idx + len(first_line_val)
            endif
        endfor

        # Fallback to the last extracted field
        if empty(target_field) && prev_field != ''
            target_field = prev_field
            target_value = prev_val
        endif
    endif

    return [target_field, target_value]
enddef

export def CursorToNext(backwards: bool = v:false, inverse: bool = v:false)
    var [target_field, target_value] = GetFieldUnderCursor()

    if empty(target_field)
        echom "Could not identify field under cursor."
        return
    endif

    var search_value = split(target_value, '\n', true)[0]
    var regex = SeekFieldBuildRegex(target_field, search_value, inverse)
    if empty(regex)
        return
    endif

    var original_pos = getpos('.')
    var original_search = @/

    execute "normal! m`"
    if backwards
        execute "normal 0"
    endif

    var search_flags = backwards ? 'bW' : 'W'
    var found_lnum = search(regex, search_flags)
    @/ = original_search

    if found_lnum > 0
        CursorToField(target_field)
    else
        setpos('.', original_pos)
    endif
enddef

nnoremap <C-n>  <Cmd>call gst_debug#CursorToNext(v:false)        <CR>
nnoremap <C-p>  <Cmd>call gst_debug#CursorToNext(v:true)         <CR>
nnoremap g<C-n> <Cmd>call gst_debug#CursorToNext(v:false, v:true)<CR>
nnoremap g<C-p> <Cmd>call gst_debug#CursorToNext(v:true,  v:true)<CR>

def NextElement()
enddef
def NextLevel()
enddef
def NextThread()
enddef

def NextLevelError()
enddef
def NextLevelWarning()
enddef
def NextLevelFixme()
enddef
def NextLevelInfo()
enddef
def NextLevelDebug()
enddef
def NextLevelLog()
enddef
def NextLevelTrace()
enddef
def NextLevelMemdump()
enddef


def PrevElement()
enddef
def PrevLevel()
enddef
def PrevThread()
enddef

def PrevLevelError()
enddef
def PrevLevelWarning()
enddef
def PrevLevelFixme()
enddef
def PrevLevelInfo()
enddef
def PrevLevelDebug()
enddef
def PrevLevelLog()
enddef
def PrevLevelTrace()
enddef
def PrevLevelMemdump()
enddef

###################################################
##  Info
###################################################

def ListElements()
enddef
def ListLevels()
enddef
def ListThreads()
enddef

###################################################
##  Filters
###################################################

def FilterLevelLower()
    # Similar to modifying GST_DEBUG= but after log is printed
enddef
def FilterBuffer()
    # Opens a buffer with all unique ids for relevant fields, lets you delete to filter out
enddef
def FilterText()
    # Arbitary grep from input
enddef
def FilterVisual()
    # Arbitrary grep from visual selection
enddef

def VimRegexToPCRE(vim_regex: string): string
    var pcre = vim_regex
    pcre = substitute(pcre, '\\%(\(.\{-}\)\\)\\@!', '(?!\1)', 'g') # Negative Lookahead: \%(X\)\@! -> (?!X)
    pcre = substitute(pcre, '\\%(', '(?:', 'g')                    # Non-capturing groups: \%(X\) -> (?:X)
    pcre = substitute(pcre, '\\)', ')', 'g')                       # Escaped parenthesis: \) -> )
    pcre = substitute(pcre, '\\x', '[0-9a-fA-F]', 'g')             # Hexadecimal character class: \x -> [0-9a-fA-F]
    pcre = substitute(pcre, '\\+', '+', 'g')                       # One or more: \+ -> +
    pcre = substitute(pcre, '\\=', '?', 'g')                       # Zero or one: \= -> ?
    return pcre
enddef

export def FilterField(field: string, inverse: bool = false)
    const cur_pos = getcurpos()
    const [obj, __, __] = ParseMultiLine(cur_pos[1])
    const value = get(obj, field, '')

    if value == ''
        echom "Cannot parse " .. field .. " field from current line. Must be in schema."
        return
    endif

    const vim_regex = SeekFieldBuildRegex(field, value, inverse)
    const pcre_regex = VimRegexToPCRE(vim_regex)
    execute $":%!rg -P '{pcre_regex}'"

    # Attempt to restore cursor safely
    const old_line_pattern = '^' .. obj.timestamp .. '\s\+' .. obj.pid .. '\s\+' .. obj.thread
    cursor(1, 1)
    if !search(old_line_pattern, 'W')
        echom "Filter applied. Original line was filtered out."
    else
        cursor(0, cur_pos[2])
    endif
enddef

def FilterReset()
enddef

###################################################
##  Filetype
###################################################

export def FTypeDetectGstreamerlogs()
    # If the filetype is already set to something, bail out
    if &filetype != '' | return | endif

    # Count how many lines start with the GStreamer timestamp format
    # If 5 or more lines match, assign the filetype
    var lines = getline(1, 20)
    var match_count = 0
    for line in lines
        if line =~# '^\d\+:\d\+:\d\+\.\d\+'
            match_count += 1
        endif
    endfor

    if match_count >= 5
        setlocal filetype=gstreamerlogs
    endif
enddef


# Expect a combo of timestamp + thread + process
# export def LineStringGet
# enddef

# export def LineStringJump
#     # ripgrep based
# enddef
# def ListUnique(method: string)
#     # if method in ["first", "last", "both"]
#     # Filter by description
# enddef
