#!/usr/bin/env bash
set -e

# Default to standard XDG userland paths if env vars are not provided
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/share/vim-gst-debug}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"

REPO_URL="https://github.com/pabsan-0/vim-gst-debug.git"
PAGINATE_REPO_URL="https://github.com/pabsan-0/vim-paginate.git"
PAGINATE_DIR="${PAGINATE_DIR:-$HOME/.local/share/vim-paginate}"

echo "==> Checking dependencies..."

if ! command -v git >/dev/null 2>&1; then
    echo "Error: git is required for the installation." >&2
    exit 1
fi

if ! command -v vim >/dev/null 2>&1; then
    echo "Error: vim is required." >&2
    exit 1
fi

if ! vim --clean -es \
    -c 'if !has("vim9script") | cquit | endif' \
    -c 'qa' >/dev/null 2>&1; then
    echo "Error: vim-gst-debug requires Vim 9 with +vim9script." >&2
    exit 1
fi

if ! command -v rg >/dev/null 2>&1; then
    echo "Error: ripgrep (rg) is required by vim-paginate." >&2
    exit 1
fi

for dep in split wc df; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        echo "Error: coreutils '$dep' is required by vim-paginate." >&2
        exit 1
    fi
done

echo "==> Installing vim-gst-debug..."

# Clone or update the repository
if [ -d "$INSTALL_DIR" ]; then
    echo "==> Updating existing installation in $INSTALL_DIR..."
    git -C "$INSTALL_DIR" pull --ff-only
else
    echo "==> Cloning repository into $INSTALL_DIR..."
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

echo "==> Installing vim-paginate..."
if [ -d "$PAGINATE_DIR/.git" ]; then
    echo "==> Updating existing vim-paginate in $PAGINATE_DIR..."
    git -C "$PAGINATE_DIR" pull --ff-only
else
    echo "==> Cloning vim-paginate into $PAGINATE_DIR..."
    mkdir -p "$(dirname "$PAGINATE_DIR")"
    git clone "$PAGINATE_REPO_URL" "$PAGINATE_DIR"
fi

if ! command -v rg >/dev/null 2>&1; then
    echo "WARNING: ripgrep (rg) was not found; vim-paginate search will be unavailable." >&2
fi

# Generate a standalone minimal vimrc
# Don't like these? either seek and edit the file, or **maintain your own vimrc**
echo "==> Generating standalone configuration..."
VIMRC_FILE="$INSTALL_DIR/vimrc"
cat << 'EOF' > "$VIMRC_FILE"
" Foundation
set nocompatible
set t_RV=
set t_RF=
set t_RB=

" Log-reading performance
set synmaxcol=500
set lazyredraw
set nowrap
set sidescroll=1
set sidescrolloff=5

" Search and UI
set incsearch
set hlsearch
set mouse=a
set shortmess+=I
set cursorline
set number
set relativenumber
set laststatus=2
set statusline=%F
hi StatusLine ctermbg=white ctermfg=black

" Disk hygiene
set noswapfile
set nobackup
set nowritebackup

" Add the plugin to the runtimepath so its ftplugin/syntax files load
let s:root = expand('<sfile>:p:h')
let &runtimepath = s:root . ',' . &runtimepath
filetype plugin indent on
syntax on

" Load only this plugin, not any other plugin scripts
execute 'source ' . fnameescape(s:root . '/plugin/gst_debug.vim')

" Viewer default: allow quitting without saving modifications
autocmd QuitPre * if &filetype ==# 'gstreamerlogs' | setlocal nomodified | endif

" Optional pre-read pager mode: gst-debug -p
if $GSTDEBUG_PAGINATE ==# '1'
    let &runtimepath = $GSTDEBUG_PAGINATE_DIR . ',' . &runtimepath
    execute 'source ' . fnameescape($GSTDEBUG_PAGINATE_DIR . '/plugin/paginate.vim')

    function! GstDebugPagerInit()
        let l:fname = expand('%:p')
        try
            PagerInit
        catch
        endtry

        if get(b:, 'paginate', v:false)
            setlocal filetype=gstreamerlogs
            return
        endif

        let l:eventignore = &eventignore
        set eventignore+=BufReadCmd
        try
            execute 'edit ' . fnameescape(l:fname)
        finally
            let &eventignore = l:eventignore
        endtry
    endfunction

    autocmd BufReadCmd * ++once call GstDebugPagerInit()
endif
EOF

# Generate the wrapper script
# Escape $# and $1 so they evaluate at runtime, but let INSTALL_DIR/VIMRC_FILE expand now
echo "==> Generating executable wrapper..."
WRAPPER_SCRIPT="$INSTALL_DIR/gst-debug"
cat << EOF > "$WRAPPER_SCRIPT"
#!/usr/bin/env bash

usage() {
    echo "Usage: gst-debug [-p|--paginate] <file>"
}

paginate=0

while [ "\$#" -gt 0 ]; do
    case "\$1" in
        -p|--paginate)
            paginate=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Unknown option: \$1" >&2
            usage
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

if [ "\$#" -ne 1 ]; then
    usage
    exit 1
fi

file="\$1"

if [ "\$paginate" -eq 1 ]; then
    if [ ! -f "\$file" ]; then
        echo "Error: not a file: \$file" >&2
        exit 1
    fi

    if [ ! -f "${PAGINATE_DIR}/plugin/paginate.vim" ]; then
        echo "Error: vim-paginate not found at ${PAGINATE_DIR}" >&2
        echo "Re-run install.sh to install it." >&2
        exit 1
    fi

    GSTDEBUG_PAGINATE=1 GSTDEBUG_PAGINATE_DIR="${PAGINATE_DIR}" exec vim --clean --noplugin \\
        -u "${VIMRC_FILE}" \\
        -c 'GstLog' \\
        -- "\$file"
fi

# --clean ignores user vimrc/plugins for a pure, fast, isolated pager experience
# --noplugin prevents loading any other plugin scripts
# -u loads our dedicated minimal config; GstLog forces the log filetype
exec vim --clean --noplugin \\
    -u "${VIMRC_FILE}" \\
    -c 'GstLog' \\
    -- "\$file"
EOF

chmod +x "$WRAPPER_SCRIPT"

# Create the symlink
echo "==> Creating symlink in $BIN_DIR..."
mkdir -p "$BIN_DIR"
ln -sf "$WRAPPER_SCRIPT" "$BIN_DIR/gst-debug"

echo ""
echo "vim-gst-debug installed successfully!"
echo ""
echo "Usage: gst-debug example.log"
echo "       gst-debug -p example.log   # paginate before loading (uses vim-paginate)"
echo ""
echo "vim-paginate installed at: $PAGINATE_DIR"
echo ""
echo "To uninstall:"
echo "  rm -f \"$BIN_DIR/gst-debug\""
echo "  rm -rf \"$INSTALL_DIR\""
echo "  rm -rf \"$PAGINATE_DIR\""
echo "Remove the PATH export from your shell rc if you added it."

# PATH sanity check
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo ""
    echo "WARNING: $BIN_DIR is not currently in your system PATH."
    echo "To use the 'gst-debug' command globally, add this to your ~/.bashrc or ~/.zshrc:"
    echo "export PATH=\"\$PATH:$BIN_DIR\""
fi
