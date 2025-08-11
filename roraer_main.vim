vim9script

var ime_job: job = null_job
var ime_channel: channel = null_channel
var ime_enabled = false
var saved_mappings: dict<dict<any>> = {}
var last_word = ''
var should_stopi = false
var pending_keys = []

# TODO: include the last few (| breaks things due to Vim syntax)
const PRINTABLE_CHARS = map(range(33, 123), (_, n) => nr2char(n))
const SPECIAL_KEYS = {
    '<Space>': ' ', '<Tab>': '\t', '<CR>': '\n', '<BS>': '\b', '<Del>': '\x7f', '<Esc>': '\e'
}

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
            IMEProcessOutput(chars)
            last_word = ''
        elseif line =~ '^error:'
            var error = UnescapeString(substitute(line, '^error:', '', ''))
            echom "IME error:" error
            last_word = ''
        endif
    endfor
enddef

def IMEUpdateWordDisplay(word: string)
    if !empty(word)
        last_word = word
    endif
    if exists('*nvim_buf_set_extmark')
        # TODO: something cooler for Neovim
    elseif exists('*prop_clear') && exists('*prop_add')
        prop_clear(line('.'), line('.'), {'type': 'ime_word_state'})
        if !empty(word)
            # TODO: actually parse the ANSI escape sequences
            var cleaned = substitute(word, '\e\[[0-9;]*m', '', 'g')
            prop_add(line('.'), col('.'), {'text': ' ' .. cleaned, 'type': 'ime_word_state'})
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
    if should_stopi
        feedkeys(chars[: -2] .. "\e", 'n')
        for key in pending_keys
            feedkeys(key, 'n')
        endfor
        pending_keys = []
        should_stopi = false
    else
        var i = 0
        while i < len(chars)
            var char = chars[i]
            if char == '\'
                if i + 1 < len(chars)
                    feedkeys(chars[i + 1], 'n')
                    i += 1
                else
                    feedkeys("\n", 'n')
                endif
            else
               feedkeys(char, 'n')
            endif
            i += 1
        endwhile
    endif
enddef

def EscapeString(str: string): string
    return escape(str, "\\\n:")
enddef

def UnescapeString(str: string): string
    return substitute(str, '\\\(.\)', '\1', 'g')
enddef

def g:IMEHandleKey(key: string)
    if should_stopi
        add(pending_keys, key)
        return
    endif
    if !ime_enabled || ime_channel == null_channel
        feedkeys(key, 'n')
        return
    endif
    
    try
        if (key ==# "\e") && !empty(last_word)
            should_stopi = true
            ch_sendraw(ime_channel, " ")
        else
            echom "Sending to IME" key "end"
            ch_sendraw(ime_channel, key)
        endif
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
    for char in PRINTABLE_CHARS + keys(SPECIAL_KEYS)
        execute printf(
            'inoremap <silent> %s <Cmd>call g:IMEHandleKey("%s")<CR>',
            char, get(SPECIAL_KEYS, char, escape(char, '\"'))
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
        
        if !empty(dataset)
            ch_sendraw(ime_channel, 'raw:' .. EscapeString(dataset) .. "\n")
        endif
        ch_sendraw(ime_channel, "\n")
        
        IMESetupMappings()
        if exists('*prop_type_add')
            call prop_type_delete('ime_word_state')
            call prop_type_add('ime_word_state', {'highlight': 'Underlined'})
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
