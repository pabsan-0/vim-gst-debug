augroup GstreamerLogDetect
    autocmd!
    autocmd BufRead,BufNewFile *.log call gst_debug#FTypeDetectGstreamerlogs()
augroup END
