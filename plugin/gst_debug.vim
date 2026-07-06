vim9script

if exists('g:loaded_gst_debug')
    finish
endif
g:loaded_gst_debug = 1

# TODO
# g:gst_debug__indent_on_load = 1
# g:gst_debug__large_file_threshold = 1

# Parse environment here
# TODO VIM_GST_DEBUG_SRC


export def FTypeSetGstreamerlogs()
    setlocal filetype=gstreamerlogs
enddef

command! GstLog call FTypeSetGstreamerlogs()
