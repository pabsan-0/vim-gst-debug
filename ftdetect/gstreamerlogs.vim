vim9script

augroup GstreamerLogDetect
    autocmd!
    autocmd BufRead,BufNewFile *.log gst_debug#FTypeDetectGstreamerlogs()
augroup END
