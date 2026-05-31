vim9script

def OnLoad()
    # Misc optimizations targeting large files
    setlocal noswapfile
    setlocal noundofile
    setlocal foldmethod=manual
    setlocal nofoldenable

    # Disable copilot on the current buffer
    # Proven to slow writing a LOT
    b:copilot_enabled = 0

    # Load ft-related plugin files
    runtime! indent/gstreamerlogs.vim
    runtime! syntax/gstreamerlogs.vim

    # Apply indentation if file is small, else message
    # silent! normal gg=G
enddef
OnLoad()


# FIXME find better names!
command! GstDebugParseLine gst_debug#ParseLineDebug()
command! GstDebugSeekLine  gst_debug#SeekFieldDebug()

command! FilterElement  gst_debug#FilterField("u_element_name")
command! FilterLevel    gst_debug#FilterField("level")
command! FilterThread   gst_debug#FilterField("thread")

# Faster saving for large files: :w is now :noautocmd w
cnoreabbrev <expr> <buffer> w (getcmdtype() == ':' && getcmdline() == 'w') ? 'noautocmd w' : 'w'

# User UX
# nnoremap ]l
# nnoremap [l
# nnoremap <leader>l
