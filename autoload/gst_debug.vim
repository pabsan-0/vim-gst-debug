vim9script

# FIXME GST_DEBUG parsing
# FIXME escape codes

# Because user may not be comfortable with switching buffer views
# b:buffer_single = get(g:, gst_debug_buffer_single, true)
g:gst_debug_debug = true
g:gst_debug_multiline_scan_len = 50

const s_level_map = {
      \ 'none': 0, 'ERROR': 1, 'WARNING': 2, 'FIXME': 3,
      \ 'INFO': 4, 'DEBUG': 5, 'LOG': 6, 'TRACE': 7, 'MEMDUMP': 9,
      \ }

# Flat schema: Every physical token in the log is a primary column.
const s_schema = [
    {name: 'timestamp', parser: '\d\+:\d\+:\d\+\.\d\+', searcher: '\S',    sep: '\s\+', },
    {name: 'pid',       parser: '\d\+',                 searcher: '\d',    sep: '\s\+', },
    {name: 'thread',    parser: '0x\x\+',               searcher: '\S',    sep: '\s\+', },
    {name: 'level',     parser: '[A-Z]\+',              searcher: '[A-Z]', sep: '\s\+', },
    {name: 'category',  parser: '\S\+',                 searcher: '\S',    sep: '\s\+', },
    {name: 'file',      parser: '[^:]\+',               searcher: '[^:]',  sep: ':',    },
    {name: 'lineno',    parser: '\d\+',                 searcher: '\d',    sep: ':',    },
    {name: 'function',  parser: '[^:]\+',               searcher: '[^:]',  sep: ':',    },
    {name: 'element',   parser: '\%(<[^>]\+>\)\=',      searcher: '[^>]',  sep: '\s*',  },
    {name: 'message',   parser: '.*',                   searcher: '.',     sep: '',     }
]

# Derived schema: Expressions and combinations.
const s_derived_schema = {
    _levelnum: { parent: 'level', expr: (ctx) => s_level_map[ctx.level] },
    _fileline: { parent: 'file',  expr: (ctx) => ctx.file .. ':' .. ctx.lineno }
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

def ParseLine(a_lnum: number = -1, debug: bool = false): dict<any>
    const target_lnum = a_lnum == -1 ? line('.') : a_lnum

    var result: dict<any> = {}
    var text_to_parse = getline(target_lnum)
    var schema_field_idx = 0

    # Base schema extraction
    for regex in s_regex_chain
        var matches = matchlist(text_to_parse, regex)
        if empty(matches)
            return {}
        endif

        var remaining_fields = min([8, len(s_schema) - schema_field_idx])
        for i in range(remaining_fields)
            var field_def = s_schema[schema_field_idx]
            var val = matches[i + 1]
            result[field_def.name] = val
            schema_field_idx += 1
        endfor

        if len(s_regex_chain) > 1 && schema_field_idx < len(s_schema)
            text_to_parse = matches[9]
        endif
    endfor

    # Derived Extraction
    for [new_field, rule] in items(s_derived_schema)
        result[new_field] = rule.expr(result)
    endfor

    if debug
        echom result
    endif
    return result
enddef


def ParseMultiLine(a_lnum: number = -1, debug: bool = false): list<any>
    const lnum_scan_start = a_lnum == -1 ? line('.') : a_lnum

    var result = {}
    var lnum = -1

    # Upward scan: aims to find a matching log line
    for offset in range(g:gst_debug_multiline_scan_len)
        lnum = lnum_scan_start - offset
        if lnum <= 0
            break
        endif

        result = ParseLine(lnum)
        if !empty(result)
            break
        endif
    endfor

    # Downward scan: if a parent log line was found, append further lines to
    # last field until a new log line starts
    if !empty(result)
        var next_lnum = lnum + 1
        var eof_lnum = line('$')

        for i in range(g:gst_debug_multiline_scan_len)
            if next_lnum > eof_lnum || !empty(ParseLine(next_lnum))
                break # We hit EOF / next log message, stop gathering
            endif
            result[s_schema[-1].name] ..= "\n" .. getline(next_lnum)
            next_lnum += 1
        endfor
    endif

    if debug
        echom [result, lnum]
    endif
    return [result, lnum]
enddef

if g:gst_debug_debug == true
    command! DebugParseLine      ParseLine(-1, true)
    command! DebugParseMultiLine ParseMultiLine(-1, true)
endif

###################################################
##  Regex Generation (Ripgrep)
###################################################

# FIXME tests pending, will be used for filtering
def SeekFieldBuildRegex(target_field: string, target_value: string, is_pcre: bool = false): string
    var parent_field = target_field

    # Map derived fields back to their physical column for regex placement
    if has_key(s_derived_schema, target_field)
        parent_field = s_derived_schema[target_field].parent
    endif

    var regex = '^'
    var field_found = false
    var star = '*'

    for field in s_schema
        # The only thing we still need to translate for PCRE is Vim's \+ in separators
        var f_sep = is_pcre ? substitute(field.sep, '\V\\+', '+', 'g') : field.sep

        if field.name == parent_field
            field_found = true
            var safe_value = escape(target_value, '.\*$^~[]')

            var loose_char = has_key(s_derived_schema, target_field) ? '.' : field.searcher
            regex ..= loose_char .. star .. safe_value .. loose_char .. star .. f_sep
        else
            # We just use the searcher character class and '*' to skip the column entirely!
            regex ..= field.searcher .. star .. f_sep
        endif
    endfor

    if !field_found
        echoerr "Unknown log field: " .. target_field
        return ""
    endif

    return regex
enddef


###################################################
## Navigation - Horizontal
###################################################

export def CursorToField(fieldname: string, visual_select: bool = false)
    var lnum_scan_start = line('.')

    var [log_data, log_lnum] = ParseMultiLine(lnum_scan_start)
    if empty(log_data)
        return
    endif

    var original_line = getline(log_lnum)
    var current_offset = 0

    for field in s_schema
        var val = get(log_data, field.name, '')
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
                    cursor(log_lnum, match_idx + 1)
                    execute "normal! v"
                    if len(val_lines) > 1
                        var end_col = max([1, len(val_lines[-1])])
                        cursor(log_lnum + len(val_lines) - 1, end_col)
                    else
                        cursor(log_lnum, match_idx + len(first_line_val))
                    endif
                else
                    cursor(log_lnum, match_idx + 1)
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


# UX: ^N ^P read current field and do next/prev

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

export def FilterField(field: string)
    const [buffr, line, column; __] = getcurpos()
    const obj = ParseLine(line)
    const value = get(obj, field, '')

    if value == ''
        echom "Cannot parse " .. field .. " from current line"
        return
    endif

    # Look up the correct regex schema field using the alias map (defaults to itself)
    const schema_field = get(s_schema_aliases, field, field)
    const regex = SeekFieldBuildRegex(schema_field, value, true)
    execute $":%!grep -P '{regex}'"

    # Search fails if match found at first line
    const old_line_pattern = '^' .. obj.timestamp .. '\s\+' .. obj.pid .. '\s\+' .. obj.thread
    cursor(1, 1)
    if !search(old_line_pattern, 'W')
        echom "Unexpected error: Can't find original line after filtering!"
    endif
    cursor(0, column)
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
