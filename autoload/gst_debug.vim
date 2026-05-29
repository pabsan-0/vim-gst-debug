vim9script

var s_level_map = {
      \ 'none':    0,
      \ 'ERROR':   1,
      \ 'WARNING': 2,
      \ 'FIXME':   3,
      \ 'INFO':    4,
      \ 'DEBUG':   5,
      \ 'LOG':     6,
      \ 'TRACE':   7,
      \ 'MEMDUMP': 9,
      \ }


export def Setup()
    const curr_bufnr = bufnr("%")
    setbufvar(curr_bufnr, '&filetype',  'gstreamerlogs')
enddef
