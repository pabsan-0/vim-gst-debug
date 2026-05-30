vim9script

def FTypeSet()
    # Misc optimizations targeting large files
    setlocal noswapfile
    setlocal noundofile
    setlocal foldmethod=manual
    setlocal nofoldenable

    # Disable copilot on the current buffer
    # Proven to slow writing a LOT
    b:copilot_enabled = 0

    # Manually load plugin files instead of doing `setlocal filetype=gstreamerlogs`
    # Skips sending events that clog vim for large files (>1GB)
    runtime! indent/gstreamerlogs.vim
    runtime! syntax/gstreamerlogs.vim
enddef

def FTypeDetect()
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
        FTypeSet()
    endif
enddef

augroup GstreamerLogDetect
    autocmd!
    autocmd BufRead,BufNewFile *.log FTypeDetect()
augroup END
