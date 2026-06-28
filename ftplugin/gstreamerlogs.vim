vim9script

# Line wrapping
setlocal wrap
setlocal breakindent
setlocal breakindentopt=shift:4

setlocal noswapfile
setlocal noundofile
setlocal foldmethod=manual
setlocal nofoldenable
if &redrawtime > 250
    &redrawtime = 250
endif


# Basic field filtering
# FIXME default to current line's, but allow argument
command! FilterPID         gst_debug#FilterField("pid")
command! FilterThread      gst_debug#FilterField("thread")
command! FilterLevel       gst_debug#FilterField("level")
command! FilterCategory    gst_debug#FilterField("category")
command! FilterSource      gst_debug#FilterField("source")
command! FilterElement     gst_debug#FilterField("element")
command! FilterElementName gst_debug#FilterField("u_element_name")


# Faster saving for large files: :w is now :noautocmd w
cnoreabbrev <expr> <buffer> w (getcmdtype() == ':' && getcmdline() == 'w') ? 'noautocmd w' : 'w'

# User UX
# nnoremap ]l
# nnoremap [l
# nnoremap <leader>ll  # level lower than
# nnoremap <leader>lh  # level higher than
# nnoremap <leader>le  # level equal to
# nnoremap <C-n>
# nnoremap <C-p>


# Disable copilot on the current buffer
# Proven to slow writing a LOT
b:copilot_enabled = 0
