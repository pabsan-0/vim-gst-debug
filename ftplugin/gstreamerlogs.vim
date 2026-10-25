" Line wrapping
setlocal wrap
setlocal breakindent
setlocal breakindentopt=shift:4

setlocal noswapfile
setlocal noundofile
setlocal foldmethod=manual
setlocal nofoldenable
if &redrawtime > 250
    let &redrawtime = 250
endif

if get(g:, 'gst_debug_debug', v:false) == v:true
    command! DebugParseLine           echom gst_debug#ParseLine(-1)
    command! DebugParseMultiLine      echom gst_debug#ParseMultiLine(-1)
    command! DebugSeekFieldBuildRegex echom gst_debug#SearchFieldValueBuildRegex('category', 'GST_INIT', 0)
endif

nnoremap g1 :<C-u>call gst_debug#CursorToField('timestamp')<CR>
nnoremap g2 :<C-u>call gst_debug#CursorToField('pid')<CR>
nnoremap g3 :<C-u>call gst_debug#CursorToField('thread')<CR>
nnoremap g4 :<C-u>call gst_debug#CursorToField('level')<CR>
nnoremap g5 :<C-u>call gst_debug#CursorToField('category')<CR>
nnoremap g6 :<C-u>call gst_debug#CursorToField('file')<CR>
nnoremap g7 :<C-u>call gst_debug#CursorToField('lineno')<CR>
nnoremap g8 :<C-u>call gst_debug#CursorToField('function')<CR>
nnoremap g9 :<C-u>call gst_debug#CursorToField('element')<CR>
nnoremap g0 :<C-u>call gst_debug#CursorToField('message')<CR>

xnoremap g1 :<C-u>call gst_debug#CursorToFieldVisual('timestamp')<CR>
xnoremap g2 :<C-u>call gst_debug#CursorToFieldVisual('pid')<CR>
xnoremap g3 :<C-u>call gst_debug#CursorToFieldVisual('thread')<CR>
xnoremap g4 :<C-u>call gst_debug#CursorToFieldVisual('level')<CR>
xnoremap g5 :<C-u>call gst_debug#CursorToFieldVisual('category')<CR>
xnoremap g6 :<C-u>call gst_debug#CursorToFieldVisual('file')<CR>
xnoremap g7 :<C-u>call gst_debug#CursorToFieldVisual('lineno')<CR>
xnoremap g8 :<C-u>call gst_debug#CursorToFieldVisual('function')<CR>
xnoremap g9 :<C-u>call gst_debug#CursorToFieldVisual('element')<CR>
xnoremap g0 :<C-u>call gst_debug#CursorToFieldVisual('message')<CR>

nnoremap <C-n>  :<C-u>call gst_debug#SearchFieldUnderCursor(0, 0)<CR>
nnoremap <C-p>  :<C-u>call gst_debug#SearchFieldUnderCursor(1, 0)<CR>
nnoremap g<C-n> :<C-u>call gst_debug#SearchFieldUnderCursor(0, 1)<CR>
nnoremap g<C-p> :<C-u>call gst_debug#SearchFieldUnderCursor(1, 1)<CR>


for s:level in ['error', 'warn', 'fixme', 'info', 'debug', 'log', 'trace', 'memdump']
    let s:cmd_name = toupper(s:level[0]) . tolower(strpart(s:level, 1))

    execute 'command! NextLevel' . s:cmd_name . ' call gst_debug#SearchFieldValue("level", "' . toupper(s:level) . '", 0, 0)'
    execute 'command! PrevLevel' . s:cmd_name . ' call gst_debug#SearchFieldValue("level", "' . toupper(s:level) . '", 1, 0)'
endfor


for s:field in ['pid', 'thread', 'level', 'category', 'file', 'lineno', 'function', 'element']
    let s:cmd_name = toupper(s:field[0]) . tolower(strpart(s:field, 1))

    execute 'command! -nargs=? Next' . s:cmd_name . 'Same call gst_debug#SearchFieldCommand("' . s:field . '", <q-args>, 0, 0)'
    execute 'command! -nargs=? Prev' . s:cmd_name . 'Same call gst_debug#SearchFieldCommand("' . s:field . '", <q-args>, 1, 0)'
    execute 'command! -nargs=? Next' . s:cmd_name . 'Diff call gst_debug#SearchFieldCommand("' . s:field . '", <q-args>, 0, 1)'
    execute 'command! -nargs=? Prev' . s:cmd_name . 'Diff call gst_debug#SearchFieldCommand("' . s:field . '", <q-args>, 1, 1)'
endfor

" Basic field filtering
" FIXME default to current line's, but allow argument
command! FilterPID         call gst_debug#FilterField('pid')
command! FilterThread      call gst_debug#FilterField('thread')
command! FilterLevel       call gst_debug#FilterField('level')
command! FilterCategory    call gst_debug#FilterField('category')
command! FilterSource      call gst_debug#FilterField('source')
command! FilterElement     call gst_debug#FilterField('element')
command! FilterElementName call gst_debug#FilterField('u_element_name')


" Faster saving for large files: :w is now :noautocmd w
cnoreabbrev <expr> <buffer> w (getcmdtype() == ':' && getcmdline() == 'w') ? 'noautocmd w' : 'w'

" User UX
" nnoremap ]l
" nnoremap [l
" nnoremap <leader>ll  " level lower than
" nnoremap <leader>lh  " level higher than
" nnoremap <leader>le  " level equal to
" nnoremap <C-n>
" nnoremap <C-p>


" Disable copilot on the current buffer
" Proven to slow writing a LOT
let b:copilot_enabled = 0
