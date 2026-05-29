if exists('b:current_syntax')
  finish
endif

syntax match GstTimestamp /^\d\+:\d\+:\d\+\.\d\+/            nextgroup=GstPid      skipwhite
syntax match GstPid       /\d\+/                  contained  nextgroup=GstThread   skipwhite
syntax match GstThread    /0x\x\+/                contained  nextgroup=@GstLevels  skipwhite

syntax cluster GstLevels contains=GstLevelError,GstLevelWarning,GstLevelFixme,GstLevelInfo,GstLevelDebug,GstLevelLog
syntax match GstLevelError   /\<ERROR\>/          contained  nextgroup=GstCategory  skipwhite
syntax match GstLevelWarning /\<WARNING\>/        contained  nextgroup=GstCategory  skipwhite
syntax match GstLevelFixme   /\<FIXME\>/          contained  nextgroup=GstCategory  skipwhite
syntax match GstLevelInfo    /\<INFO\>/           contained  nextgroup=GstCategory  skipwhite
syntax match GstLevelDebug   /\<DEBUG\>/          contained  nextgroup=GstCategory  skipwhite
syntax match GstLevelLog     /\<LOG\>/            contained  nextgroup=GstCategory  skipwhite
syntax match GstLevelTrace   /\<TRACE\>/          contained  nextgroup=GstCategory  skipwhite
syntax match GstLevelMemdump /\<MEMDUMP\>/        contained  nextgroup=GstCategory  skipwhite

syntax match GstCategory /\S\+/                   contained  nextgroup=GstSource    skipwhite
syntax match GstSource /\f\+\.\(c\|cpp\|h\|hpp\|py\|rs\|go\):\d\+:[A-Za-z_][A-Za-z0-9_]*/ contained

syntax match GstContinuation /^[^0-9].*/
syntax match GstContinuation /^\s\+.*/


highlight default GstTimestamp    ctermfg=244  guifg=#888888
highlight default GstPid          ctermfg=244  guifg=#888888
highlight default GstThread       ctermfg=238  guifg=#555555

highlight default GstLevelError   ctermfg=196  guifg=#ff2020  cterm=bold gui=bold
highlight default GstLevelWarning ctermfg=214  guifg=#ffaa00  cterm=bold gui=bold
highlight default GstLevelFixme   ctermfg=226  guifg=#ffff00
highlight default GstLevelInfo    ctermfg=40   guifg=#00cc00
highlight default GstLevelDebug   ctermfg=33   guifg=#3399ff
highlight default GstLevelLog     ctermfg=239  guifg=#666666

highlight default GstCategory     ctermfg=183  guifg=#cc99ff  cterm=bold gui=bold
highlight default GstSource       ctermfg=73   guifg=#66cccc
highlight default GstContinuation cterm=italic gui=italic

let b:current_syntax = 'gstreamerlogs'
