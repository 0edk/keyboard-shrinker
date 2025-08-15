vim9script

var ime_job: job = null_job
var ime_channel: channel = null_channel
var ime_enabled = false
var saved_mappings: dict<dict<any>> = {}

# TODO: include the last few (| breaks things due to Vim syntax)
const PRINTABLE_CHARS = map(range(33, 123), (_, n) => nr2char(n))
const SPECIAL_KEYS = {
    '<Space>': ' ', '<Tab>': '\t', '<CR>': '\n', '<BS>': '\b', '<Del>': '\x7f'
}
const ALPHABET = "a-zA-Z0-9_'"

def IMEOutput(channel: channel, msg: string)
    if !ime_enabled
        return
    endif
    
    const lines = split(msg, "\n")
    for line in lines
        if line =~ '^word:'
            var word_text = substitute(line, '^word:', '', '')
            word_text = UnescapeString(word_text)
            IMEUpdateWordDisplay(word_text)
        elseif line =~ '^text:'
            IMEProcessOutput(substitute(line, '^text:', '', ''))
        elseif line =~ '^error:'
            const error = UnescapeString(substitute(line, '^error:', '', ''))
            echom "IME error:" error
        endif
    endfor
enddef

def CleanANSI(raw: string): string
    return substitute(raw, '\e\[[0-9;]*m', '', 'g')
enddef

def IMEUpdateWordDisplay(word: string)
    const cleaned = CleanANSI(word)
    const line_text = getline('.')
    const col_pos = col('.') - 1
    var word_start = match(
        line_text[: col_pos],
        printf('\([^%s]\|^\)[%s]\+$', ALPHABET, ALPHABET)
    ) + 1
    if word_start == 0
        word_start = col_pos + 1
    endif
    var word_end = match(line_text, printf('\([^%s]\|$\)', ALPHABET), word_start)
    if word_end == -1
        word_end = word_start
    endif
    const prefix = word_start < 2 ? '' : line_text[: word_start - 1]
    setline('.', prefix .. cleaned .. line_text[word_end :])
    cursor(line('.'), word_start + len(cleaned) + 1)
enddef

def InsertChars(chars: string)
    const line_text = getline('.')
    setline('.', line_text[0 : col('.') - 2] .. chars .. line_text[col('.') - 1 :])
    cursor(line('.'), col('.') + len(chars))
enddef

def IMEProcessOutput(chars: string)
    if empty(chars)
        return
    endif
    var i = 0
    while i < len(chars)
        var char = chars[i]
        if char ==# '\'
            if i + 1 < len(chars)
                char = chars[i + 1]
                if char == "\x08"
                    const line_text = getline('.')
                    const suffix = line_text[col('.') - 1 :]
                    setline('.', line_text[0 : col('.') - 3] .. suffix)
                    if !empty(suffix)
                        cursor(line('.'), col('.') - 1)
                    endif
                else
                    if &expandtab && char == "\x09"
                        char = repeat(' ', &tabstop)
                    endif
                    InsertChars(char)
                endif
                i += 1
            else
                append('.', '')
                cursor(line('.') + 1, col('.'))
            endif
        else
           InsertChars(char)
        endif
        i += 1
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
        const mapping_info = maparg(char, 'i', false, true)
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
    
    const ime_executable = get(
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
        # TODO: this'll be redundant
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
    #autocmd InsertLeave * if ime_enabled | call IMEUpdateWordDisplay('') | endif
augroup END

augroup IMECleanup
    autocmd!
    autocmd VimLeavePre * call IMEDisable()
augroup END
