vim9script

def DetectGstreamerLog()
    if &filetype != '' && &filetype !=# 'text' && &filetype !=# 'log'
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
        setfiletype gstreamerlogs
    endif
enddef

augroup GstreamerLogDetect
    autocmd!
    autocmd BufRead,BufNewFile * DetectGstreamerLog()
augroup END
