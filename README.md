# vim-gst-debug

**Work in progress**

GStreamer log parsing, navigation, listing, and filtering utilities for Vim.

This plugin parses the standard GStreamer debug log line into fields, and installs a few convenience buffer-local mappings to easily navigate them along syntax highlighting.

To handle large files, this plugin will be built on [pabsan-0/vim-paginate](https://github.com/pabsan-0/vim-paginate)


## Install

```vim
Plug 'pabsan-0/vim-gst-debug'
```

## Usage

The `gstreamerlogs` filetype is assigned when either:

- Several lines at the beggining of your file match the GStreamer log format
- When manually calling `:GstLog`

```
0:00:00.000057928   203 0x613b6ef141e0 ERROR           GST_REGISTRY gstregistry.c:1605:priv_gst_get_relocated_libgstreamer: attempting to retrieve libgstreamer-1.0
```

## Features

### Horizontal movement

`g1`-`g0` move the cursor to a specific field on the current line; the same keys (now `xnoremap`) visually select that field.

```
g1        g2    g3        g4      g5          g6   g7     g8       g9       g0
timestamp pid   thread    level   category    file:lineno:function<element> message
```


## Vertical movement

Several conveniences for vertically seeking logs:

- Explicit commands: `NextLevelSame`, `NextLevelDiff`, `NextCategorySame`, `NextCategoryDiff`... (for pid, thread, level, category, file, lineno, function, element).

- Explicit commands for individial error levels: `:NextLevelError`, `:PrevLevelTrace`, ... generated for every level (for error, warn, fixme, info, debug, log, trace, memdump).

- Hijacked `<C-n> <C-p>`: While on a given field, jump to the next with the same/different value

    | Map             | Action                                    |
    |-----------------|-------------------------------------------|
    | `<C-n>`         | next line with same field under cursor    |
    | `<C-p>`         | previous line with same field under cursor|
    | `g<C-n>`        | next line where the field differs         |
    | `g<C-p>`        | previous line where the field differs     |


## Filtering

Filter the buffer to entries matching a field on the current line, using `rg` under the hood for speed.

```vim
:FilterPID :FilterThread :FilterLevel :FilterCategory
:FilterSource :FilterElement :FilterElementName
```

## Listing

**experimental**

Open a scratch buffer tabulating all unique values for a field, with count, first, and last line where it appears (built via `awk`):

| Command          | Field                           |
|------------------|---------------------------------|
| `:ListElements`  | element names (`<...>`)         |
| `:ListLevels`    | levels                          |
| `:ListCategories`| categories                      |
| `:ListSources`   | `file:lineno:function` triplets |

In this buffer:
- `g1` jump to the first appearance of the value under the cursor in the original logs
- `g2` jump to the last appearance of the value under the cursor in the original logs

<!-- ## Large-file optimizations -->

<!-- GStreamer logs are huge. The plugin takes non-standard measures to keep Vim responsive: -->

<!-- - Filetype detection avoids `setfiletype` (which fires autocmds for other plugins to react to); the source file is sourced directly instead. -->
<!-- - Copilot is disabled on `gstreamerlogs` buffers (`b:copilot_enabled = 0`) — its insert-mode polling made writing stall. -->
<!-- - `:w` is remapped to `:noautocmd w`. -->
<!-- - `noswapfile`, `noundofile`, manual folding (`foldmethod=manual`), and `redrawtime` is capped at 250ms. -->
