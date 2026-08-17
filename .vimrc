" Mapped from Cursor User settings.json (vim.* / relative line numbers)
" Cursor does not read this file.

" editor.lineNumbers: "relative"
set number
set relativenumber

" vim.useSystemClipboard: true
set clipboard^=unnamed,unnamedplus

" vim.hlsearch / vim.incsearch
set hlsearch
set incsearch

" "vim.leader": "<space>"  (commented out in Cursor; leave default)

" vim.highlightedyank.enable + duration 200
if has('nvim')
  augroup HighlightYank
    autocmd!
    autocmd TextYankPost * silent! lua vim.highlight.on_yank({higroup='IncSearch', timeout=200})
  augroup END
elseif exists('##TextYankPost') && exists('*timer_start') && exists('*matchaddpos')
  function! s:HighlightYank() abort
    if get(v:event, 'operator', '') !=# 'y'
      return
    endif
    let l:start = getpos("'[")
    let l:end = getpos("']")
    let l:positions = []
    if l:start[1] == l:end[1]
      call add(l:positions, [l:start[1], l:start[2], max([l:end[2] - l:start[2] + 1, 1])])
    else
      for l:lnum in range(l:start[1], l:end[1])
        call add(l:positions, l:lnum)
      endfor
    endif
    try
      let l:id = matchaddpos('IncSearch', l:positions)
      call timer_start(200, {-> execute('silent! call matchdelete(' . l:id . ')')})
    endtry
  endfunction
  augroup HighlightYank
    autocmd!
    autocmd TextYankPost * call s:HighlightYank()
  augroup END
endif
