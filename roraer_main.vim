vim9script

var ime_job: job = null_job
var ime_channel: channel = null_channel
var ime_enabled = false
var saved_mappings: dict<dict<any>> = {}

# TODO: include the last few (| breaks things due to Vim syntax)
const PRINTABLE_CHARS = map(range(33, 123), (_, n) => nr2char(n))
const SPECIAL_KEYS = {'<Space>': ' ', '<Tab>': '\t', '<CR>': '\n', '<BS>': '\b', '<Del>': '\x7f'}

def IMEOutput(channel: channel, msg: string)
    if !ime_enabled
        return
    endif
    
    var lines = split(msg, "\n")
    for line in lines
        if line =~ '^word:'
            var word_text = substitute(line, '^word:', '', '')
            word_text = UnescapeString(word_text)
            IMEUpdateWordDisplay(word_text)
        elseif line =~ '^text:'
            var chars = substitute(line, '^text:', '', '')
            chars = UnescapeString(chars)
            IMEProcessOutput(chars)
        elseif line =~ '^error:'
            var error = UnescapeString(substitute(line, '^error:', '', ''))
            echom "IME error:" error
        endif
    endfor
enddef

def IMEUpdateWordDisplay(word: string)
    if exists('*nvim_buf_set_extmark')
        # TODO: something cooler for Neovim
    elseif exists('*prop_clear') && exists('*prop_add')
        prop_clear(line('.'), line('.'), {'type': 'ime_word_state'})
        if !empty(word)
            prop_add(line('.'), col('.'), {'text': '[' .. word .. ']', 'type': 'ime_word_state'})
        endif
    else
        if empty(word)
            echo ''
        else
            echohl Comment | echo '[' .. word .. ']' | echohl None
        endif
    endif
enddef

def IMEProcessOutput(chars: string)
    if empty(chars)
        return
    endif
    IMEUpdateWordDisplay('')
    var i = 0
    while i < len(chars)
        var char = chars[i]
        if char == '\'
            if i + 1 < len(chars)
                var next_char = chars[i + 1]
                feedkeys(next_char, 'n')
                i += 2
            else
                feedkeys("\n", 'n')
                i += 1
            endif
        else
            feedkeys(char, 'n')
            i += 1
        endif
    endwhile
enddef

def EscapeString(str: string): string
    return escape(str, "\\\n:")
enddef

def UnescapeString(str: string): string
    return substitute(str, '\\\(.\)', '\1', 'g')
enddef

def g:IMEHandleKey(key: string)
    if !ime_enabled || ime_channel == null_channel
        feedkeys(key, 'n')
        return
    endif
    
    try
        ch_sendraw(ime_channel, key)
    catch
        echom "IME communication error:" v:exception
        IMEDisable()
        feedkeys(key, 'n')
    endtry
enddef

def IMESaveCurrentMappings()
    saved_mappings = {}
    for char in PRINTABLE_CHARS + keys(SPECIAL_KEYS)
        var mapping_info = maparg(char, 'i', false, true)
        if !empty(mapping_info)
            saved_mappings[char] = mapping_info
        endif
    endfor
enddef

def IMERestoreMappings()
    for char in PRINTABLE_CHARS + keys(SPECIAL_KEYS)
        execute printf('iunmap <silent> %s', char)
    endfor
    
    for [key, mapping_info] in items(saved_mappings)
        if !empty(mapping_info)
            var cmd = (mapping_info.noremap ? 'inoremap' : 'imap')
            cmd ..= (mapping_info.silent ? ' <silent>' : '')
            cmd ..= (mapping_info.expr ? ' <expr>' : '')
            cmd ..= ' ' .. key .. ' ' .. mapping_info.rhs
            execute cmd
        endif
    endfor
    saved_mappings = {}
enddef

def IMESetupMappings()
    for char in PRINTABLE_CHARS
        execute printf(
            'inoremap <silent> %s <Cmd>call g:IMEHandleKey("%s")<CR>',
            char, escape(char, '"')
        )
    endfor
    for [key, target] in items(SPECIAL_KEYS)
        execute printf(
            'inoremap <silent> %s <Cmd>call g:IMEHandleKey(%s)<CR>',
            key, target
        )
    endfor
enddef

export def IMEEnable(dataset_file: string = '')
    if ime_enabled
        echom "IME already enabled"
        return
    endif
    
    var ime_executable = get(
        g:, 'ime_executable',
        expand('<script>:p:h') .. '/zig-out/bin/keyboard_shrinker'
    )
    if !executable(ime_executable)
        echoerr "IME executable not found:" ime_executable
        return
    endif
    
    var dataset = empty(dataset_file) ? expand('%:p') : dataset_file
    if empty(dataset)
        echoerr "No dataset file specified and current buffer has no filename"
        return
    endif
    
    IMESaveCurrentMappings()
    
    try
        ime_job = job_start(ime_executable, {
            'in_mode': 'raw',
            'out_mode': 'raw',
            'out_cb': function('IMEOutput'),
            'close_cb': function('IMECloseCallback')
        })
        if job_status(ime_job) != 'run'
            throw "Failed to start IME process"
        endif
        ime_channel = job_getchannel(ime_job)
        
        var init_cmd = 'raw:' .. EscapeString(dataset) .. "\n\n"
        ch_sendraw(ime_channel, init_cmd)
        
        IMESetupMappings()
        if exists('*prop_type_add')
            call prop_type_delete('ime_word_state')
            call prop_type_add('ime_word_state', {'highlight': 'Comment'})
        endif
        
        ime_enabled = true
        echom "IME enabled with dataset:" fnamemodify(dataset, ':t')
    catch
        echom "Failed to start IME:" v:exception
        IMECleanup()
    endtry
enddef

def IMECloseCallback(channel: channel)
    if ime_enabled
        echom "IME process closed unexpectedly"
        IMEDisable()
    endif
enddef

export def IMEDisable()
    if !ime_enabled
        return
    endif
    
    ime_enabled = false
    IMECleanup()
    echom "IME disabled"
enddef

def IMECleanup()
    IMEUpdateWordDisplay('')
    
    if !empty(saved_mappings)
        IMERestoreMappings()
    endif
    
    if ch_status(ime_channel) ==# 'open'
        ch_close(ime_channel)
        ime_channel = null_channel
    endif
    if ime_job != null_job && job_status(ime_job) == 'run'
        job_stop(ime_job)
    endif
    ime_job = null_job
enddef

command! -nargs=? IMEEnable call IMEEnable(<q-args>)
command! IMEDisable call IMEDisable()

augroup IMEModeChange
    autocmd!
    autocmd InsertLeave * if ime_enabled | call IMEUpdateWordDisplay('') | endif
augroup END

augroup IMECleanup
    autocmd!
    autocmd VimLeavePre * call IMEDisable()
augroup END
