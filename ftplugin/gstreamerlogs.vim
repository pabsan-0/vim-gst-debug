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

if get(g:, "gst_debug_debug", v:false) == v:true
    command! DebugParseLine           echom gst_debug#ParseLine(-1)
    command! DebugParseMultiLine      echom gst_debug#ParseMultiLine(-1)
    command! DebugSeekFieldBuildRegex echom gst_debug#SeekFieldBuildRegex("category", "GST_INIT", 0)
endif

nnoremap g1 <Cmd>call gst_debug#CursorToField('timestamp')<CR>
nnoremap g2 <Cmd>call gst_debug#CursorToField('pid')<CR>
nnoremap g3 <Cmd>call gst_debug#CursorToField('thread')<CR>
nnoremap g4 <Cmd>call gst_debug#CursorToField('level')<CR>
nnoremap g5 <Cmd>call gst_debug#CursorToField('category')<CR>
nnoremap g6 <Cmd>call gst_debug#CursorToField('file')<CR>
nnoremap g7 <Cmd>call gst_debug#CursorToField('lineno')<CR>
nnoremap g8 <Cmd>call gst_debug#CursorToField('function')<CR>
nnoremap g9 <Cmd>call gst_debug#CursorToField('element')<CR>
nnoremap g0 <Cmd>call gst_debug#CursorToField('message')<CR>

xnoremap g1 <Cmd>call gst_debug#CursorToFieldVisual('timestamp')<CR>
xnoremap g2 <Cmd>call gst_debug#CursorToFieldVisual('pid')<CR>
xnoremap g3 <Cmd>call gst_debug#CursorToFieldVisual('thread')<CR>
xnoremap g4 <Cmd>call gst_debug#CursorToFieldVisual('level')<CR>
xnoremap g5 <Cmd>call gst_debug#CursorToFieldVisual('category')<CR>
xnoremap g6 <Cmd>call gst_debug#CursorToFieldVisual('file')<CR>
xnoremap g7 <Cmd>call gst_debug#CursorToFieldVisual('lineno')<CR>
xnoremap g8 <Cmd>call gst_debug#CursorToFieldVisual('function')<CR>
xnoremap g9 <Cmd>call gst_debug#CursorToFieldVisual('element')<CR>
xnoremap g0 <Cmd>call gst_debug#CursorToFieldVisual('message')<CR>

nnoremap <C-n>  <Cmd>call gst_debug#SearchFieldUnderCursor(0, 0)<CR>
nnoremap <C-p>  <Cmd>call gst_debug#SearchFieldUnderCursor(1, 0) <CR>
nnoremap g<C-n> <Cmd>call gst_debug#SearchFieldUnderCursor(0, 1)<CR>
nnoremap g<C-p> <Cmd>call gst_debug#SearchFieldUnderCursor(1, 1)<CR>


for level in ['error', 'warn', 'fixme', 'info', 'debug', 'log', 'trace', 'memdump']
    var cmd_name = toupper(level[0]) .. tolower(level[1 : ])

    execute $'command! NextLevel{level} gst_debug#SearchFieldValue("level", "{toupper(level)}", 0, 0)'
    execute $'command! PrevLevel{level} gst_debug#SearchFieldValue("level", "{toupper(level)}", 1, 0)'
endfor


for field in ['pid', 'thread', 'level', 'category', 'file', 'lineno', 'function', 'element']
    var cmd_name = toupper(field[0]) .. tolower(field[1 : ])

    execute $'command! -nargs=? Next{cmd_name}Same gst_debug#SearchFieldCommand("{field}", <q-args>, 0, 0)'
    execute $'command! -nargs=? Prev{cmd_name}Same gst_debug#SearchFieldCommand("{field}", <q-args>, 1, 0)'
    execute $'command! -nargs=? Next{cmd_name}Diff gst_debug#SearchFieldCommand("{field}", <q-args>, 0, 1)'
    execute $'command! -nargs=? Prev{cmd_name}Diff gst_debug#SearchFieldCommand("{field}", <q-args>, 1, 1)'
endfor

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
