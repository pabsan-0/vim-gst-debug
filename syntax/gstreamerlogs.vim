if exists('b:current_syntax')
  finish
endif

syntax sync clear
syntax sync minlines=1 maxlines=1

" Anchored at the start; parsing timestamps precisely is already optimal
syntax match GstTimestamp /^\d\+:\d\+:\d\+\.\d\+/            nextgroup=GstPid      skipwhite
syntax match GstPid       /\d\+/                  contained  nextgroup=GstThread   skipwhite
syntax match GstThread    /0x\x\+/                contained  nextgroup=@GstLevels  skipwhite

syntax cluster GstLevels contains=GstLevelError,GstLevelWarning,GstLevelFixme,GstLevelInfo,GstLevelDebug,GstLevelLog,GstLevelTrace,GstLevelMemdump
syntax keyword GstLevelError   ERROR   contained nextgroup=GstCategory skipwhite
syntax keyword GstLevelWarning WARNING contained nextgroup=GstCategory skipwhite
syntax keyword GstLevelFixme   FIXME   contained nextgroup=GstCategory skipwhite
syntax keyword GstLevelInfo    INFO    contained nextgroup=GstCategory skipwhite
syntax keyword GstLevelDebug   DEBUG   contained nextgroup=GstCategory skipwhite
syntax keyword GstLevelLog     LOG     contained nextgroup=GstCategory skipwhite
syntax keyword GstLevelTrace   TRACE   contained nextgroup=GstCategory skipwhite
syntax keyword GstLevelMemdump MEMDUMP contained nextgroup=GstCategory skipwhite

syntax match GstCategory /\S\+/                   contained  nextgroup=GstSource   skipwhite
syntax match GstSource   /\S\+:\d\+:\S\+/         contained
syntax match GstContinuation /^[^0-9].*/


highlight default GstTimestamp    ctermfg=244  guifg=#888888
highlight default GstPid          ctermfg=244  guifg=#888888
highlight default GstThread       ctermfg=238  guifg=#555555

highlight default GstLevelError   ctermfg=196  guifg=#ff2020  cterm=bold gui=bold
highlight default GstLevelWarning ctermfg=214  guifg=#ffaa00  cterm=bold gui=bold
highlight default GstLevelFixme   ctermfg=226  guifg=#ffff00
highlight default GstLevelInfo    ctermfg=40   guifg=#00cc00
highlight default GstLevelDebug   ctermfg=33   guifg=#3399ff
highlight default GstLevelLog     ctermfg=239  guifg=#666666
highlight default GstLevelTrace   ctermfg=13   guifg=#ff00ff
highlight default GstLevelMemdump ctermfg=14   guifg=#00ffff

highlight default GstCategory     ctermfg=183  guifg=#cc99ff  cterm=bold gui=bold
highlight default GstSource       ctermfg=73   guifg=#66cccc
highlight default GstContinuation cterm=italic gui=italic

let b:current_syntax = 'gstreamerlogs'
