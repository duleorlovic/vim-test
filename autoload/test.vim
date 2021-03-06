function! test#run(type, arguments) abort
  if &autowrite || &autowriteall
    silent! wall
  endif

  if exists('g:test#project_root')
    execute 'cd' g:test#project_root
  endif

  if exists('g:projectionist_heuristics')
    let alternate_file = get(filter(projectionist#query_file('alternate'), 'filereadable(v:val)'), 0)
  endif

  if test#test_file(expand('%'))
    let position = s:get_position(expand('%'))
    let g:test#last_position = position
  elseif exists('alternate_file') && !empty(alternate_file) && test#test_file(alternate_file)
    let position = s:get_position(alternate_file)
  elseif exists('g:test#last_position')
    let position = g:test#last_position
  else
    call s:echo_failure('Not a test file') | return
  endif

  let runner = test#determine_runner(position['file'])

  let args = test#base#build_position(runner, a:type, position)
  let args = a:arguments + args
  let args = test#base#options(runner, a:type) + args

  if type(get(g:, 'test#strategy')) == type({})
    let strategy = get(g:test#strategy, a:type)
    call test#execute(runner, args, strategy)
  else
    call test#execute(runner, args)
  endif

  if exists('g:test#project_root')
    execute 'cd -'
  endif
endfunction

function! test#run_last(arguments) abort
  if exists('g:test#last_command')
    let strategy = s:extract_strategy_from_command(a:arguments)

    if empty(strategy)
      let strategy = g:test#last_strategy
    endif

    let cmd = [g:test#last_command]
    let cmd = cmd + a:arguments

    call test#shell(join(cmd), strategy)
  else
    call s:echo_failure('No tests were run so far')
  endif
endfunction

function! test#visit() abort
  if exists('g:test#last_position')
    execute 'edit' '+'.g:test#last_position['line'] g:test#last_position['file']
  else
    call s:echo_failure('No tests were run so far')
  endif
endfunction

function! test#execute(runner, args, ...) abort
  let strategy = s:extract_strategy_from_command(a:args)
  if empty(strategy)
    if !empty(a:000)
      let strategy = a:1
    else
      let strategy = get(g:, 'test#strategy')
    endif
  endif
  if empty(strategy)
    let strategy = 'basic'
  endif

  let args = a:args
  let args = test#base#options(a:runner) + args
  call filter(args, '!empty(v:val)')

  let executable = test#base#executable(a:runner)
  let args = test#base#build_args(a:runner, args)
  let cmd = [executable] + args
  call filter(cmd, '!empty(v:val)')

  call test#shell(join(cmd), strategy)
endfunction

function! test#shell(cmd, strategy) abort
  let g:test#last_command = a:cmd
  let g:test#last_strategy = a:strategy

  let cmd = a:cmd

  if has_key(g:, 'test#transformation')
    let cmd = g:test#custom_transformations[g:test#transformation](cmd)
  endif

  if cmd =~# '^:'
    let strategy = 'vimscript'
  else
    let strategy = a:strategy
  endif

  if has_key(g:test#custom_strategies, strategy)
    call g:test#custom_strategies[strategy](cmd)
  else
    call test#strategy#{strategy}(cmd)
  endif
endfunction

function! test#determine_runner(file) abort
  for [language, runners] in items(g:test#runners)
    for runner in runners
      let runner = tolower(language).'#'.tolower(runner)
      if test#base#test_file(runner, fnamemodify(a:file, ':.'))
        return runner
      endif
    endfor
  endfor
endfunction

function! test#test_file(file) abort
  return !empty(test#determine_runner(a:file))
endfunction

function! s:get_position(path) abort
  let filename_modifier = get(g:, 'test#filename_modifier', ':.')

  let position = {}
  let position['file'] = fnamemodify(a:path, filename_modifier)
  let position['line'] = a:path == expand('%') ? line('.') : 1
  let position['col']  = a:path == expand('%') ? col('.') : 1

  return position
endfunction

function! s:extract_strategy_from_command(arguments) abort
  for idx in range(0, len(a:arguments) - 1)
    if a:arguments[idx] =~# '^-strategy='
      return substitute(remove(a:arguments, idx), '-strategy=', '', '')
    endif
  endfor
endfunction

function! s:echo_failure(message) abort
  echohl WarningMsg
  echo a:message
  echohl None
endfunction
