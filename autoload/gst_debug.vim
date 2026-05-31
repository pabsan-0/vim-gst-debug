vim9script

var s_level_map = {
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

###################################################
##  Filters
###################################################

# FilterThread
# FilterElement
# FilterBuffer (?)

def Filter()
    bufnr_src = bufnr('%')
    curr_line = getline('.')
    # Parse current Line for current Filtering-whatever-Name
    # Parse current Line for current Timestamp and Thread (to retrieve location later)

    # Is user on a view buffer?
    if !getbufvar(bufnr_src, "gst_debug_is_view", false)
        bufnr_src = CreateViewBuffer()
    endif

    # Grab original text buffer
    if !getbufvar(-1, "gst_debug_original_file", false)
        CreateViewBuffer()
    endif

    # Populate view buffer with outcome of the parsing

    # Return to old line
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
