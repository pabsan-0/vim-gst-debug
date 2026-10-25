if exists('g:loaded_gst_debug')
    finish
endif
let g:loaded_gst_debug = 1

" TODO
" let g:gst_debug__indent_on_load = 1
" let g:gst_debug__large_file_threshold = 1

" Parse environment here
" TODO VIM_GST_DEBUG_SRC


function! s:FTypeSetGstreamerlogs() abort
    setlocal filetype=gstreamerlogs
endfunction

command! GstLog call <SID>FTypeSetGstreamerlogs()
