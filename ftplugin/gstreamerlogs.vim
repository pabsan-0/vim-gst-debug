vim9script

def OnLoad()
    # Misc optimizations targeting large files
    setlocal noswapfile
    setlocal noundofile
    setlocal foldmethod=manual
    setlocal nofoldenable
    if &redrawtime > 250
        &redrawtime = 250
    endif

    # Disable copilot on the current buffer
    # Proven to slow writing a LOT
    b:copilot_enabled = 0

    # Load ft-related plugin files
    runtime! indent/gstreamerlogs.vim
    runtime! syntax/gstreamerlogs.vim

    # Apply indentation if file is small, else message
    # silent! normal gg=G

    const abuf = bufnr('%')
    augroup GstDebugRgSearch
        execute $'autocmd! * <buffer={abuf}>'
        execute $'autocmd CmdlineChanged <buffer={abuf}> if getcmdtype() ==# "/" | gst_debug#CmdlineChanged() | endif'
    augroup END

    nnoremap <silent> <buffer> n <ScriptCmd>gst_debug#RgNext()<CR>
    nnoremap <silent> <buffer> N <ScriptCmd>gst_debug#RgPrev()<CR>
    nnoremap <silent> <buffer> * <ScriptCmd>gst_debug#RgWord()<CR>
    cnoremap <expr> <buffer> <CR> getcmdtype() ==# '/' ? "\<C-c>\<ScriptCmd>gst_debug#RgInterceptCR()\<CR>" : "\<CR>"
enddef
OnLoad()


# FIXME find better names!
command! GstDebugParseLine gst_debug#ParseLineDebug()
command! GstDebugSeekLine  gst_debug#SeekFieldDebug()

# Basic field filtering
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
# nnoremap <leader>l
