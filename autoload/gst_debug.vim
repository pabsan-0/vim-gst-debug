vim9script

const s_level_map = {
      \ 'none':    0,
      \ 'ERROR':   1,
      \ 'WARNING': 2,
      \ 'FIXME':   3,
      \ 'INFO':    4,
      \ 'DEBUG':   5,
      \ 'LOG':     6,
      \ 'TRACE':   7,
      \ 'MEMDUMP': 9,
      \ }

# Vim can only have 9 groups in a single regex. These are the basic blocks
const s_regex_schema = [
    {name: 'timestamp', precise: '\d\+:\d\+:\d\+\.\d\+', loose: '\S',    sep: '\s\+'},
    {name: 'pid',       precise: '\d\+',                 loose: '\d',    sep: '\s\+'},
    {name: 'thread',    precise: '0x\x\+',               loose: '\S',    sep: '\s\+'},
    {name: 'level',     precise: '[A-Z]\+',              loose: '[A-Z]', sep: '\s\+'},
    {name: 'category',  precise: '\S\+',                 loose: '\S',    sep: '\s\+'},
    {name: 'source',    precise: '[^:]\+:\d\+:[^:]\+',   loose: '\S',    sep: ':'},
    {name: 'element',   precise: '\%(<[^>]\+>\)\=',      loose: '[^>]',  sep: '\s*'},
    {name: 'message',   precise: '.*',                   loose: '.',     sep: ''}
]

# Keys are strings parsed from the line with more than the above regex
# Then they is searched as it were part of the Value field
const s_schema_aliases = {
    'u_element_name': 'element',
}


###################################################
##  Parsing
###################################################

export def ParseLineDebug()
    var lnum = line('.')
    var result = ParseLine(lnum)
    if empty(result)
        echom "Current Line does not match the GStreamer log header format."
        return
    endif
    echom result
enddef

def ParseLineBuildRegex(): string
    var regex = '^'
    for field in s_regex_schema
        regex ..= '\(' .. field.precise .. '\)' .. field.sep
    endfor
    return regex
enddef

def ParseLineCurrent()
    return ParseLine(line('.'))
enddef

def ParseLine(lnum: number): dict<any>
    var result: dict<any> = {}
    const pattern = ParseLineBuildRegex()

    var line_str = getline(lnum)
    var matches = matchlist(line_str, pattern)
    if empty(matches)
        return {}
    endif

    # Populate the initial dictionary
    result['timestamp'] = matches[1]
    result['pid']       = str2nr(matches[2])
    result['thread']    = matches[3]
    result['level']     = matches[4]
    result['category']  = matches[5]
    result['source']    = matches[6]
    result['element']   = trim(matches[7], "<>")
    result['message']   = matches[8]

    # Convoluted conveniences (not straight out of regex)
    const src_parts = split(result['source'], ':')
    result['u_file']     = src_parts[0]
    result['u_lineno']   = str2nr(src_parts[1])
    result['u_function'] = src_parts[2]

    result['u_element_name'] = get(split(result['element'], '@'), 0, '')
    result['u_levelnum'] = get(s_level_map, matches[4], -1)
    result['u_fileline'] = result['u_file'] .. ":" .. result['u_lineno']

    # Look ahead to grab any lines that do not start with a timestamp
    var current_lnum = lnum + 1
    var last_lnum = line('$')
    var timestamp_pattern = '^\d\+:\d\+:\d\+\.\d\+'

    while current_lnum <= last_lnum
        var next_line = getline(current_lnum)

        if next_line =~ timestamp_pattern
            break
        endif

        if result['message'] == ''
            result['message'] = next_line
        else
            result['message'] ..= "\n" .. next_line
        endif
        current_lnum += 1
    endwhile

    return result
enddef

###################################################
##  Seeking
###################################################

export def SeekFieldDebug()
    var lnum = line('.')

    for item in s_regex_schema
        const name = item.name
        echom name
        echom SeekFieldBuildRegex(name, "FOOBAR")
        echom
    endfor
enddef

def SeekFieldBuildRegex(target_field: string, target_value: string, is_pcre: bool = false): string
    var regex = '^'
    var field_found = false
    var star = '*'

    for field in s_regex_schema
        # Translate Vim's \+ to PCRE's + for external tools like ripgrep
        var f_precise = is_pcre ? substitute(field.precise, '\\+', '+', 'g') : field.precise
        f_precise = is_pcre ? substitute(f_precise, '\\x', '[0-9a-fA-F]', 'g') : f_precise
        var f_sep     = is_pcre ? substitute(field.sep, '\\+', '+', 'g')   : field.sep

        if field.name == target_field
            field_found = true
            var safe_value = escape(target_value, '.\*$^~[]')
            regex ..= field.loose .. star .. safe_value .. field.loose .. star .. f_sep
            break
        else
            regex ..= f_precise .. f_sep
        endif
    endfor

    if !field_found
        echoerr "Unknown log field: " .. target_field
        return ""
    endif

    return regex
enddef


###################################################
##  Navigation
###################################################

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

def FTypeSetGstreamerlogs()
    # Manually load plugin files instead of doing `setlocal filetype=gstreamerlogs`
    # Skips sending events that clog vim for large files (>1GB)
    runtime! ftplugin/gstreamerlogs.vim
enddef


export def FTypeDetectGstreamerlogs()
    # If the filetype is already set to something, bail out
    if &filetype != ''
        return
    endif

    var lines = getline(1, 10)
    var match_count = 0

    # Count how many lines start with the GStreamer timestamp format
    # If 5 or more lines match, assign the filetype
    for line in lines
        if line =~# '^\d\+:\d\+:\d\+\.\d\+'
            match_count += 1
        endif
    endfor

    if match_count >= 5
        FTypeSetGstreamerlogs()
    endif
enddef

###################################################
##  Rg search
###################################################

var s_rg_matches: list<list<number>> = []
var s_rg_index: number = -1
var s_rg_pattern: string = ''
var s_rg_job: job = null_job
var s_cmdline_pattern: string = ''

def VimToPcre(pattern: string): string
    var pcre = pattern
    pcre = substitute(pcre, '\V\\+', '+', 'g')
    pcre = substitute(pcre, '\V\\|', '|', 'g')
    pcre = substitute(pcre, '\V\\(', '(', 'g')
    pcre = substitute(pcre, '\V\\)', ')', 'g')
    pcre = substitute(pcre, '\V\\x', '[0-9a-fA-F]', 'g')
    pcre = substitute(pcre, '\V\\<', '\b', 'g')
    pcre = substitute(pcre, '\V\\>', '\b', 'g')
    return pcre
enddef

def ParseVimgrepLine(line_str: string): list<number>
    const parts = split(line_str, ':')
    if len(parts) < 3
        return []
    endif

    const lnum = str2nr(parts[-3])
    const col = str2nr(parts[-2])
    if lnum <= 0 || col <= 0
        return []
    endif

    return [lnum, col]
enddef

def FindFirstAfter(matches: list<list<number>>, cur_lnum: number, cur_col: number): number
    for i in range(len(matches))
        const [lnum, col] = matches[i]
        if lnum > cur_lnum || (lnum == cur_lnum && col > cur_col)
            return i
        endif
    endfor
    return len(matches) > 0 ? 0 : -1
enddef

def JumpToIndex(index: number)
    if index < 0 || index >= len(s_rg_matches)
        return
    endif

    const [lnum, col] = s_rg_matches[index]
    cursor(lnum, col)
enddef

export def CmdlineChanged()
    s_cmdline_pattern = getcmdline()
enddef

def StopRgJob()
    if s_rg_job != null_job && job_status(s_rg_job) ==# 'run'
        job_stop(s_rg_job)
    endif
    s_rg_job = null_job
enddef

export def RgTriggerAsync(pattern: string)
    StopRgJob()

    const rg_pattern = VimToPcre(pattern)
    const cur_lnum = line('.')
    const cur_col = col('.')
    const file_path = expand('%:p')
    var acc: list<string> = []

    s_rg_job = job_start(['rg', '--vimgrep', '--pcre2', '--no-messages', '-e', rg_pattern, file_path], {
        out_mode: 'nl',
        out_cb: (_, msg) => add(acc, msg),
        err_mode: 'nl',
        err_cb: (_, __) => {},
        exit_cb: (_, code) => RgJobDone(copy(acc), cur_lnum, cur_col, code),
    })
enddef

def RgJobDone(raw: list<string>, cur_lnum: number, cur_col: number, code: number)
    s_rg_job = null_job
    if code != 0
        s_rg_matches = []
        s_rg_index = -1
        return
    endif

    var matches: list<list<number>> = []
    for entry in raw
        const parsed = ParseVimgrepLine(entry)
        if !empty(parsed)
            add(matches, parsed)
        endif
    endfor

    if empty(matches)
        s_rg_matches = []
        s_rg_index = -1
        return
    endif

    s_rg_matches = matches
    s_rg_index = FindFirstAfter(s_rg_matches, cur_lnum, cur_col)
    echom $'rg: {len(s_rg_matches)} matches [{s_rg_index + 1}/{len(s_rg_matches)}]'
enddef

export def RgInterceptCR()
    const pattern = s_cmdline_pattern
    if pattern == ''
        return
    endif

    s_rg_pattern = pattern
    s_rg_matches = []
    s_rg_index = -1
    @/ = pattern
    set hlsearch
    RgTriggerAsync(pattern)

    const rg_pattern = VimToPcre(pattern)
    const cur_lnum = line('.')
    const cur_col = col('.')
    const file_path = expand('%:p')
    const raw = systemlist(['rg', '--vimgrep', '--pcre2', '--no-messages', '-e', rg_pattern, file_path])
    if v:shell_error != 0
        echo "Pattern not found"
        return
    endif

    var matches: list<list<number>> = []
    for entry in raw
        const parsed = ParseVimgrepLine(entry)
        if !empty(parsed)
            add(matches, parsed)
        endif
    endfor

    const first_idx = FindFirstAfter(matches, cur_lnum, cur_col)
    if first_idx < 0
        echo "Pattern not found"
        return
    endif

    const [lnum, col] = matches[first_idx]
    cursor(lnum, col)
enddef

export def RgNext()
    if empty(s_rg_matches) || @/ !=# s_rg_pattern
        normal! n
        return
    endif

    s_rg_index = (s_rg_index + 1) % len(s_rg_matches)
    JumpToIndex(s_rg_index)
enddef

export def RgPrev()
    if empty(s_rg_matches) || @/ !=# s_rg_pattern
        normal! N
        return
    endif

    s_rg_index = (s_rg_index - 1 + len(s_rg_matches)) % len(s_rg_matches)
    JumpToIndex(s_rg_index)
enddef

export def RgWord()
    const word = expand('<cword>')
    if word == ''
        return
    endif

    s_cmdline_pattern = '\<' .. escape(word, '\') .. '\>'
    RgInterceptCR()
enddef
