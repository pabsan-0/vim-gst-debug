vim9script

if exists('g:loaded_gst_debug')
    finish
endif
g:loaded_gst_debug = 1

# Parse environment here
# TODO VIM_GST_DEBUG_SRC

command! GstLog call gst_debug#Setup()
