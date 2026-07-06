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
    _findexpr: { parent: 'file',  expr: (ctx) => "^" .. ctx.timestamp .. '\s\+' .. ctx.pid .. '\s\+' .. ctx.thread}
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


def SearchFieldValueBuildRegex(target_field: string, target_value: string, inverse: bool = false): string
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


export def SearchFieldValue(fieldname: string, value: string, backwards: bool = false, inverse: bool = false): bool
    var regex = SearchFieldValueBuildRegex(fieldname, value, inverse)
    echom regex

    if empty(regex)
        return false
    endif

    var original_pos = getpos('.')
    var original_search = @/

    execute "normal! m`"

    # If searching backwards, jump to column 1 so we don't match the current line
    if backwards
        execute "normal! 0"
    endif

    var search_flags = backwards ? 'bW' : 'W'
    var found_lnum = search(regex, search_flags)
    @/ = original_search

    if found_lnum > 0
        CursorToField(fieldname)
        return true
    else
        setpos('.', original_pos)
        return false
    endif
enddef

###################################################
## Navigation - Horizontal
###################################################

def GetFieldUnderCursor(): list<string>
    const [fields, locs, lnum] = ParseMultiLine(line('.'))
    if empty(fields) | return ['', ''] | endif

    var fieldname = ''
    var fieldvalue = ''

    # Continuation line of a multiline block
    if line('.') > lnum
        fieldname = s_schema[-1].name
        fieldvalue = get(fields, fieldname, '')
    else
        for fieldschema in s_schema
            if has_key(locs, fieldschema.name) && locs[fieldschema.name].col <= col('.')
                fieldname = fieldschema.name
                fieldvalue = get(fields, fieldname, '')
            else
                break
            endif
        endfor
    endif

    return [fieldname, fieldvalue]
enddef


export def CursorToField(fieldname: string, do_visual_select: bool = false)
    var [fields, locs, lnum] = ParseMultiLine(line('.'))
    if empty(fields) || !has_key(locs, fieldname)
        return
    endif

    execute "normal! m`"
    cursor(locs[fieldname].line, locs[fieldname].col)
enddef


export def CursorToFieldVisual(fieldname: string)
    var [fields, locs, lnum] = ParseMultiLine(line('.'))
    if empty(fields) || !has_key(locs, fieldname)
        return
    endif
    execute "normal! m`"

    var end_line = -1
    var end_col  = -1

    var val_lines = split(fields[fieldname], '\n', true)
    if len(val_lines) > 1
        end_line = locs[fieldname].line + len(val_lines) - 1
        end_col  = max([1, len(val_lines[-1])])
    else
        end_line = locs[fieldname].line
        end_col  = locs[fieldname].col + len(fields[fieldname]) - 1
    endif

    cursor(locs[fieldname].line, locs[fieldname].col)
    execute "normal! \<Esc>v"
    cursor(end_line, end_col)
enddef


###################################################
## Navigation - Vertical
###################################################

export def SearchFieldUnderCursor(backwards: bool = false, inverse: bool = false)
    var [target_field, target_value] = GetFieldUnderCursor()

    if empty(target_field)
        echom "Could not identify field under cursor."
        return
    endif

    var search_value = split(target_value, '\n', true)[0]
    SearchFieldValue(target_field, search_value, backwards, inverse)
enddef


export def SearchFieldFromCurrentLine(target_field: string, backwards: bool = false, inverse: bool = false)
    const [fields, locs, line_log_start] = ParseMultiLine()
    if empty(fields)
        echom $"Could not identify field {target_field}"
        return
    endif

    var target_value = get(fields, target_field, '')
    var search_value = split(target_value, '\n', true)[0]
    SearchFieldValue(target_field, search_value, backwards, inverse)
enddef


export def SearchFieldCommand(target_field: string, target_value: string = "", backwards: bool = false, inverse: bool = false)
    if target_value == ""
        SearchFieldFromCurrentLine(target_field, backwards, inverse)
    else
        SearchFieldValue(target_field, target_value, backwards, inverse)
    endif
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
def ListUnique()
    # show first last both so I can press Enter
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

export def FilterField(fieldname: string, inverse: bool = false)
    const cur_pos = getcurpos()
    const fields = ParseMultiLine(cur_pos[1])[0]
    const value = get(fields, fieldname, '')

    if value == ''
        echom "Cannot parse " .. fieldname .. " field from current line. Must be in schema."
        return
    endif

    const vim_regex = SearchFieldValueBuildRegex(fieldname, value, inverse)
    const pcre_regex = VimRegexToPCRE(vim_regex)
    execute $":%!rg -P '{pcre_regex}'"

    # Attempt to restore cursor safely
    cursor(1, 1)
    if !search(fields._findexpr, 'cw')
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
