" FIXME GST_DEBUG parsing
" FIXME escape codes

" Because user may not be comfortable with switching buffer views
" let b:buffer_single = get(g:, gst_debug_buffer_single, 1)
let g:gst_debug_debug = 1
let g:gst_debug_multiline_scan_len = 50

let s:level_map = {
      \ 'none': 0, 'ERROR': 1, 'WARN': 2, 'FIXME': 3,
      \ 'INFO': 4, 'DEBUG': 5, 'LOG': 6, 'TRACE': 7, 'MEMDUMP': 9
      \ }

" Flat schema: Every physical token in the log is a primary column.
let s:schema = [
    \ {'name': 'timestamp', 'parser': '\d\+:\d\+:\d\+\.\d\+', 'sep': '\s\+'},
    \ {'name': 'pid',       'parser': '\d\+',                 'sep': '\s\+'},
    \ {'name': 'thread',    'parser': '0x\x\+',               'sep': '\s\+'},
    \ {'name': 'level',     'parser': '[A-Z]\+',              'sep': '\s\+'},
    \ {'name': 'category',  'parser': '\S\+',                 'sep': '\s\+'},
    \ {'name': 'file',      'parser': '[^:]\+',               'sep': ':'},
    \ {'name': 'lineno',    'parser': '\d\+',                 'sep': ':'},
    \ {'name': 'function',  'parser': '[^:]\+',               'sep': ':'},
    \ {'name': 'element',   'parser': '\%(<[^>]\+>\)\=',      'sep': '\s*'},
    \ {'name': 'message',   'parser': '.*',                   'sep': ''}
    \ ]

" Derived schema: Expressions and combinations.
let s:derived_schema = {
    \ '_source':   {'parent': 'level', 'expr': {ctx -> ctx.file . ':' . ctx.lineno . ':' . ctx.function}},
    \ '_levelnum': {'parent': 'level', 'expr': {ctx -> s:level_map[ctx.level]}},
    \ '_findexpr': {'parent': 'file',  'expr': {ctx -> '^' . ctx.timestamp . '\s\+' . ctx.pid . '\s\+' . ctx.thread}}
    \ }

" Yields a list of regexes to parse a line.
" Each regex captures 8 groups and packs the rest of the line in the 9th.
" This allows chained parsing to overcome Vim's 9 capture groups limitation.
function! s:BuildRegexChain() abort
    let regex_chain = []
    let current_regex = '^'
    let group_count = 0

    for field in s:schema
        " If we'd need a 9th capture group, capture the rest of the line
        " and initiate a new pattern
        if group_count == 8
            " Close the current pattern and append it to the output list
            let current_regex .= '\(.*\)'
            call add(regex_chain, current_regex)

            " Initiate a new pattern
            let current_regex = '^'
            let group_count = 0
        endif

        let current_regex .= '\(' . field.parser . '\)' . field.sep
        let group_count += 1
    endfor

    " Add the ongoing pattern to the output list
    if current_regex !=# '^'
        call add(regex_chain, current_regex)
    endif

    return regex_chain
endfunction
let s:regex_chain = s:BuildRegexChain()


"###################################################
""  Parsing anf seeking
"###################################################

function! gst_debug#ParseLine(...) abort
    let lnum = a:0 > 0 ? a:1 : -1
    let target_lnum = lnum == -1 ? line('.') : lnum

    " Outcomes
    let fields = {}
    let locs = {}

    " Helpers
    let original_line = getline(target_lnum)
    let to_parse = original_line
    let field_idx = 0
    let offset = 0

    " Base schema extraction
    for regex in s:regex_chain
        let matches = matchlist(to_parse, regex)
        if empty(matches)
            return [fields, locs, target_lnum]
        endif

        let remaining_fields = min([8, len(s:schema) - field_idx])
        for i in range(remaining_fields)
            let field_name = s:schema[field_idx].name
            let val = matches[i + 1]

            " Store the field value
            let fields[field_name] = val

            " And its location if not null
            if val !=# ''
                let match_idx = stridx(original_line, val, offset)
                if match_idx >= 0
                    let locs[field_name] = {'line': target_lnum, 'col': match_idx + 1}
                    let offset = match_idx + len(val)
                endif
            endif
            let field_idx += 1
        endfor

        if len(s:regex_chain) > 1 && field_idx < len(s:schema)
            let to_parse = matches[9]
        endif
    endfor

    " Derived Extraction
    for pair in items(s:derived_schema)
        let new_field = pair[0]
        let rule = pair[1]
        let fields[new_field] = call(rule.expr, [fields])
        if has_key(locs, rule.parent)
            let locs[new_field] = copy(locs[rule.parent])
        endif
    endfor

    return [fields, locs, target_lnum]
endfunction


function! gst_debug#ParseMultiLine(...) abort
    let lnum_scan_start = a:0 > 0 ? a:1 : -1
    if lnum_scan_start == -1
        let lnum_scan_start = line('.')
    endif

    let fields = {}
    let locs = {}
    let line_log_start = -1

    " Upward scan: aims to find a schema-matching log line
    for line_offset in range(g:gst_debug_multiline_scan_len)
        let lnum = lnum_scan_start - line_offset
        if lnum <= 0
            break
        endif

        let [fields, locs, line_log_start] = gst_debug#ParseLine(lnum)
        if !empty(fields) && !empty(locs)
            break
        endif
    endfor

    " Downward scan: if log line was found, append further lines to last field
    let eof_lnum = line('$')
    let last_field_name = s:schema[-1].name
    if !empty(fields)
        for line_offset in range(g:gst_debug_multiline_scan_len)
            let lnum = line_log_start + line_offset + 1

            let parsed = gst_debug#ParseLine(lnum)
            if !empty(parsed[0]) || lnum > eof_lnum
                break
            endif

            let fields[last_field_name] .= "\n" . getline(lnum)
        endfor
    endif

    return [fields, locs, line_log_start]
endfunction


function! gst_debug#SearchFieldValueBuildRegex(target_field, target_value, ...) abort
    let inverse = a:0 > 0 ? a:1 : 0
    let field_found = 0
    let regex = '^'

    for field in s:schema
        if field.name ==# a:target_field
            let field_found = 1
            let target_value_safe = escape(a:target_value, '.\*$^~[]')

            if inverse
                let regex .= '\%(' . target_value_safe . '\)\@!' . field.parser
            else
                let regex .= target_value_safe
            endif
            break
        else
            let regex .= field.parser . field.sep
        endif
    endfor

    if !field_found
        echoerr 'Unknown log field: ' . a:target_field
        return ''
    endif

    return regex
endfunction


function! gst_debug#SearchFieldValue(fieldname, value, ...) abort
    let backwards = a:0 >= 1 ? a:1 : 0
    let inverse = a:0 >= 2 ? a:2 : 0
    let regex = gst_debug#SearchFieldValueBuildRegex(a:fieldname, a:value, inverse)
    echom regex

    if empty(regex)
        return 0
    endif

    let original_pos = getpos('.')
    let original_search = @/

    execute "normal! m`"

    " If searching backwards, jump to column 1 so we don't match the current line
    if backwards
        execute 'normal! 0'
    endif

    let search_flags = backwards ? 'bW' : 'W'
    let found_lnum = search(regex, search_flags)
    let @/ = original_search

    if found_lnum > 0
        call gst_debug#CursorToField(a:fieldname)
        return 1
    else
        call setpos('.', original_pos)
        return 0
    endif
endfunction

"###################################################
"" Navigation - Horizontal
"###################################################

function! s:GetFieldUnderCursor() abort
    let parsed = gst_debug#ParseMultiLine(line('.'))
    let fields = parsed[0]
    let locs = parsed[1]
    let lnum = parsed[2]
    if empty(fields)
        return ['', '']
    endif

    let fieldname = ''
    let fieldvalue = ''

    " Continuation line of a multiline block
    if line('.') > lnum
        let fieldname = s:schema[-1].name
        let fieldvalue = get(fields, fieldname, '')
    else
        for fieldschema in s:schema
            if has_key(locs, fieldschema.name) && locs[fieldschema.name].col <= col('.')
                let fieldname = fieldschema.name
                let fieldvalue = get(fields, fieldname, '')
            else
                break
            endif
        endfor
    endif

    return [fieldname, fieldvalue]
endfunction


function! gst_debug#CursorToField(fieldname, ...) abort
    let parsed = gst_debug#ParseMultiLine(line('.'))
    let fields = parsed[0]
    let locs = parsed[1]
    if empty(fields) || !has_key(locs, a:fieldname)
        return
    endif

    execute "normal! m`"
    call cursor(locs[a:fieldname].line, locs[a:fieldname].col)
endfunction


function! gst_debug#CursorToFieldVisual(fieldname) abort
    let parsed = gst_debug#ParseMultiLine(line('.'))
    let fields = parsed[0]
    let locs = parsed[1]
    if empty(fields) || !has_key(locs, a:fieldname)
        return
    endif
    execute "normal! m`"

    let end_line = -1
    let end_col  = -1

    let val_lines = split(fields[a:fieldname], '\n', 1)
    if len(val_lines) > 1
        let end_line = locs[a:fieldname].line + len(val_lines) - 1
        let end_col  = max([1, len(val_lines[-1])])
    else
        let end_line = locs[a:fieldname].line
        let end_col  = locs[a:fieldname].col + len(fields[a:fieldname]) - 1
    endif

    call cursor(locs[a:fieldname].line, locs[a:fieldname].col)
    execute "normal! \<Esc>v"
    call cursor(end_line, end_col)
endfunction


"###################################################
"" Navigation - Vertical
"###################################################

function! gst_debug#SearchFieldUnderCursor(...) abort
    let backwards = a:0 >= 1 ? a:1 : 0
    let inverse = a:0 >= 2 ? a:2 : 0
    let target = s:GetFieldUnderCursor()
    let target_field = target[0]
    let target_value = target[1]

    if empty(target_field)
        echom 'Could not identify field under cursor.'
        return
    endif

    let value_lines = split(target_value, '\n', 1)
    call gst_debug#SearchFieldValue(target_field, value_lines[0], backwards, inverse)
endfunction


function! gst_debug#SearchFieldFromCurrentLine(target_field, ...) abort
    let backwards = a:0 >= 1 ? a:1 : 0
    let inverse = a:0 >= 2 ? a:2 : 0
    let parsed = gst_debug#ParseMultiLine()
    let fields = parsed[0]
    if empty(fields)
        echom 'Could not identify field ' . a:target_field
        return
    endif

    let target_value = get(fields, a:target_field, '')
    let value_lines = split(target_value, '\n', 1)
    call gst_debug#SearchFieldValue(a:target_field, value_lines[0], backwards, inverse)
endfunction


function! gst_debug#SearchFieldCommand(target_field, ...) abort
    let target_value = a:0 >= 1 ? a:1 : ''
    let backwards = a:0 >= 2 ? a:2 : 0
    let inverse = a:0 >= 3 ? a:3 : 0
    if target_value ==# ''
        call gst_debug#SearchFieldFromCurrentLine(a:target_field, backwards, inverse)
    else
        call gst_debug#SearchFieldValue(a:target_field, target_value, backwards, inverse)
    endif
endfunction


"###################################################
""  Lists
"###################################################

" FIXME clean up.
" jump_type is either "first" or "last" (not enforced)
function! s:JumpToAppearance(jump_type) abort
    let line_text = getline('.')
    let target_field = b:target_field

    if line_text =~# '^[-|[:space:]]\+$' || line_text =~# 'Count'
        return
    endif

    let parts = split(line_text, '\s*|\s*')
    if len(parts) < 4
        return
    endif

    " Extract and trim the padding from the scratch buffer table
    let target_val = trim(a:jump_type ==# 'first' ? parts[2] : parts[3])
    let target_buf = get(b:, 'gst_log_bufnr', -1)

    if target_buf == -1 || !bufexists(target_buf)
        echom 'Original log buffer not found or closed.'
        return
    endif

    let winid = bufwinid(target_buf)
    if winid != -1
        call win_gotoid(winid)
    else
        execute 'sbuffer ' . target_buf
    endif

    call cursor(1, 1)

    " \V enables "very nomagic", making all characters literal.
    " We include the ^ anchor to ensure we only match the start of the line.
    let search_pattern = '\V\^' . escape(target_val, '\')

    if search(search_pattern, 'cw') > 0
        normal! zz
        call gst_debug#CursorToField(target_field)
    else
        echom 'Could not find appearance: ' . target_val
    endif
endfunction

" FIXME have awk script files as assets. Try to regularize for regex single-source-of-truth
function! s:ListField(target_field) abort
    let log_bufnr = bufnr('%')
    echom 'Scanning buffer for ' . a:target_field . 's via awk...'

    let awk_script =<< trim CODE
        BEGIN {
            num_unique = 0
        }
        {
            # 1. Enforce strict log conformance.
            # Matches: timestamp + spaces + PID + spaces + thread (0xHEX)
            if (!match($0, /^[0-9]+:[0-9]+:[0-9]+\.[0-9]+[ \t]+[0-9]+[ \t]+0x[0-9a-fA-F]+/)) {
                next
            }

            # Capture the exact literal prefix string for Vim to jump to later
            jump_str = substr($0, RSTART, RLENGTH)

            # Strip ANSI escape codes
            gsub(/\x1B\\[[0-9;]*[a-zA-Z]/, "")

            val = ""
            if (target == "element") {
                if (match($6, /<[^>]+>/)) {
                    val = substr($6, RSTART + 1, RLENGTH - 2)
                }
            } else if (target == "level") {
                val = $4
            } else if (target == "category") {
                val = $5
            } else if (target == "source") {
                split($6, a, ":")
                val = a[1] ":" a[2] ":" a[3]
            }

            if (val != "") {
                if (!(val in count)) {
                    order[++num_unique] = val
                    first_jump[val] = jump_str
                }
                count[val]++
                last_jump[val] = jump_str
            }
        }
        END {
            if (num_unique == 0) {
                print "No matching log entries found."
                exit
            }

            # 1. Establish baseline widths using the text lengths of the headers
            max_v = length("Value")
            max_c = length("Count")
            max_f = length("First Appearance")
            max_l = length("Last Appearance")

            # 2. Iterate through values to calculate true maximum column widths
            for (i = 1; i <= num_unique; i++) {
                v = order[i]
                if (length(v) > max_v) max_v = length(v)
                if (length(count[v]) > max_c) max_c = length(count[v])
                if (length(first_jump[v]) > max_f) max_f = length(first_jump[v])
                if (length(last_jump[v]) > max_l) max_l = length(last_jump[v])
            }

            # 3. Dynamically construct format string templates based on computed widths
            # (Using '%%' outputs a literal '%' character into the final format template string)
            fmt_header = sprintf("%%-%ds | %%-%ds | %%-%ds | %%-%ds\n", max_v, max_c, max_f, max_l)
            fmt_row    = sprintf("%%-%ds | %%-%dd | %%-%ds | %%-%ds\n", max_v, max_c, max_f, max_l)

            # 4. Generate a completely responsive divider line matching the widths
            sep_v = ""; for (j = 1; j <= max_v; j++) sep_v = sep_v "-"
            sep_c = ""; for (j = 1; j <= max_c; j++) sep_c = sep_c "-"
            sep_f = ""; for (j = 1; j <= max_f; j++) sep_f = sep_f "-"
            sep_l = ""; for (j = 1; j <= max_l; j++) sep_l = sep_l "-"
            sep_line = sep_v "-+-" sep_c "-+-" sep_f "-+-" sep_l

            # 5. Output the calculated table structures
            printf fmt_header, "Value", "Count", "First Appearance", "Last Appearance"
            print sep_line

            for (i = 1; i <= num_unique; i++) {
                v = order[i]
                printf fmt_row, v, count[v], first_jump[v], last_jump[v]
            }
        }
    CODE

    let temp_awk = tempname()
    call writefile(awk_script, temp_awk)

    let output = []
    let clean_target = tolower(a:target_field)

    if !&modified && !empty(expand('%'))
        let cmd = 'awk -v target=' . shellescape(clean_target) . ' -f ' . shellescape(temp_awk) . ' ' . shellescape(expand('%'))
        let output = systemlist(cmd)
    else
        let cmd = 'awk -v target=' . shellescape(clean_target) . ' -f ' . shellescape(temp_awk)
        let output = systemlist(cmd, getline(1, '$'))
    endif

    call delete(temp_awk)

    if v:shell_error != 0
        echoerr 'Failed to parse logs using awk.'
        return
    endif

    execute 'new'
    setlocal buftype=nofile bufhidden=wipe nobuflisted noswapfile
    setlocal cursorline

    let title = toupper(clean_target[0]) . strpart(clean_target, 1) . 's'
    execute 'silent! file [GStreamer ' . title . ']'

    call setline(1, output)

    let b:gst_log_bufnr = log_bufnr
    let b:target_field = a:target_field


    syntax match TableDimmed /\.\d\+\s\+\d\+\s\+0x\x\+/
    syntax match TableStructure /[\|]/
    syntax match TableDivider /^-\++\+.\+$/
    hi def link TableDimmed NonText
    hi def link TableStructure Special
    hi def link TableDivider Comment

    nnoremap <buffer> <silent> g1 :<C-u>call <SID>JumpToAppearance('first')<CR>
    nnoremap <buffer> <silent> g2 :<C-u>call <SID>JumpToAppearance('last')<CR>

    setlocal nomodifiable
endfunction


command! ListElements   call <SID>ListField('element')
command! ListLevels     call <SID>ListField('level')
command! ListCategories call <SID>ListField('category')
command! ListSources    call <SID>ListField('source')

"###################################################
""  Filters
"###################################################

function! s:FilterLevelLower() abort
    " Similar to modifying GST_DEBUG= but after log is printed
endfunction
function! s:FilterBuffer() abort
    " Opens a buffer with all unique ids for relevant fields, lets you delete to filter out
endfunction
function! s:FilterText() abort
    " Arbitary grep from input
endfunction
function! s:FilterVisual() abort
    " Arbitrary grep from visual selection
endfunction

function! s:VimRegexToPCRE(vim_regex) abort
    let pcre = a:vim_regex
    let pcre = substitute(pcre, '\\%(\(.\{-}\)\\)\\@!', '(?!\1)', 'g') " Negative Lookahead: \%(X\)\@! -> (?!X)
    let pcre = substitute(pcre, '\\%(', '(?:', 'g')                    " Non-capturing groups: \%(X\) -> (?:X)
    let pcre = substitute(pcre, '\\)', ')', 'g')                       " Escaped parenthesis: \) -> )
    let pcre = substitute(pcre, '\\x', '[0-9a-fA-F]', 'g')             " Hexadecimal character class: \x -> [0-9a-fA-F]
    let pcre = substitute(pcre, '\\+', '+', 'g')                       " One or more: \+ -> +
    let pcre = substitute(pcre, '\\=', '?', 'g')                       " Zero or one: \= -> ?
    return pcre
endfunction

function! gst_debug#FilterField(fieldname, ...) abort
    let inverse = a:0 > 0 ? a:1 : 0
    let cur_pos = getcurpos()
    let parsed = gst_debug#ParseMultiLine(cur_pos[1])
    let fields = parsed[0]
    let value = get(fields, a:fieldname, '')

    if value ==# ''
        echom 'Cannot parse ' . a:fieldname . ' field from current line. Must be in schema.'
        return
    endif

    let vim_regex = gst_debug#SearchFieldValueBuildRegex(a:fieldname, value, inverse)
    let pcre_regex = s:VimRegexToPCRE(vim_regex)
    execute "%!rg -P '" . pcre_regex . "'"

    " Attempt to restore cursor safely
    call cursor(1, 1)
    if !search(fields._findexpr, 'cw')
        echom 'Filter applied. Original line was filtered out.'
    else
        call cursor(0, cur_pos[2])
    endif
endfunction

function! s:FilterReset() abort
endfunction

"###################################################
""  Filetype
"###################################################

function! gst_debug#FTypeDetectGstreamerlogs() abort
    " If the filetype is already set to something, bail out
    if &filetype !=# ''
        return
    endif

    " Count how many lines start with the GStreamer timestamp format
    " If 5 or more lines match, assign the filetype
    let lines = getline(1, 20)
    let match_count = 0
    for line in lines
        if line =~# '^\d\+:\d\+:\d\+\.\d\+'
            let match_count += 1
        endif
    endfor

    if match_count >= 5
        setlocal filetype=gstreamerlogs
    endif
endfunction
