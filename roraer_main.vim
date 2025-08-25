vim9script

var ime_job: job = null_job
var ime_channel: channel = null_channel
var ime_enabled = false
var saved_mappings: dict<dict<any>> = {}

const PRINTABLE_CHARS = map(range(33, 126), (_, n) => nr2char(n))
const SPECIAL_KEYS = {
    '<Space>': ' ', '<Tab>': '\t', '<CR>': '\n', '<BS>': '\b', '<Del>': '\x7f', '<Esc>': '\e'
}
const ALPHABET = "a-zA-Z0-9_"
const IME_NAME = 'Roraer'

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
    const col_pos = col('.') - 2
    var word_start = col_pos
    while word_start >= 0 && line_text[word_start] =~ '[' .. ALPHABET .. ']'
        word_start -= 1
    endwhile
    const prefix = word_start < 0 ? '' : line_text[: word_start]
    setline('.', prefix .. cleaned .. line_text[col_pos + 1 :])
    cursor(line('.'), word_start + len(cleaned) + 2)
enddef

def InsertChars(chars: string)
    feedkeys(chars, 'n')
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
                i += 1
                char = chars[i]
            else
                char = "\n"
            endif
        endif
        InsertChars(char)
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
        var tkey = key
        if key == "\e"
            stopinsert
            tkey = "\x04"
        endif
        ch_sendraw(ime_channel, tkey)
    catch
        echom "IME communication error:" v:exception
        IMEDisable()
        feedkeys(key, 'n')
    endtry
enddef

def SaveCurrentMappings()
    saved_mappings = {}
    for char in PRINTABLE_CHARS + keys(SPECIAL_KEYS)
        const mapping_info = maparg(char, 'i', false, true)
        if !empty(mapping_info)
            saved_mappings[char] = mapping_info
        endif
    endfor
enddef

def RestoreMappings()
    for char in PRINTABLE_CHARS + keys(SPECIAL_KEYS)
        execute printf('iunmap <silent> %s', char == '|' ? '\|' : char)
    endfor
    
    for [key, mapping_info] in items(saved_mappings)
        if !empty(mapping_info)
            var cmd = (mapping_info.noremap ? 'inoremap' : 'imap')
            cmd ..= (mapping_info.silent ? ' <silent>' : '')
            cmd ..= (mapping_info.expr ? ' <expr>' : '')
            cmd ..= ' ' .. escape(key, '|') .. ' ' .. mapping_info.rhs
            execute cmd
        endif
    endfor
    saved_mappings = {}
enddef

def SetupMappings()
    for char in PRINTABLE_CHARS + keys(SPECIAL_KEYS)
        execute printf(
            'inoremap <silent> %s <Cmd>call g:IMEHandleKey("%s")<CR>',
            escape(char, '|'), get(SPECIAL_KEYS, char, escape(char, '"\|'))
        )
    endfor
enddef

def ProjectList(): list<string>
    if empty(expand('%'))
        return []
    else
        return split(glob(expand('%:h') .. '/**/*.' .. expand('%:e')), "\n")
    endif
enddef

def LoadDataset(path: string, mode = 'raw')
    ch_sendraw(ime_channel, mode .. ':' .. EscapeString(path) .. "\n")
enddef

export def IMEEnable(dataset_file: string = '')
    if ime_enabled
        echom IME_NAME "already enabled"
        return
    endif
    const ime_executable = tolower(IME_NAME)
    if ch_status(ime_channel) !=# 'open'
        if !executable(ime_executable)
            echom "IME executable not found:" ime_executable
            return
        endif
    endif
    SaveCurrentMappings()
    try
        if ch_status(ime_channel) !=# 'open'
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
            if !empty(&syntax)
                const syntax_dir = get(
                    g:, 'ime_syntax',
                    expand('<script>:p:h') .. '/syntax'
                )
                if isdirectory(syntax_dir)
                    const syntax_file = syntax_dir .. '/' .. &syntax
                    if filereadable(syntax_file)
                        LoadDataset(syntax_file)
                    else
                        echom "No syntax guide for" &syntax
                    endif
                endif
            endif
            if empty(dataset_file)
                for file in ProjectList()
                    LoadDataset(file)
                endfor
            else
                LoadDataset(dataset_file)
            endif
            ch_sendraw(ime_channel, "\n")
        endif
        SetupMappings()
        ime_enabled = true
        echom printf(
            "%s enabled %s",
            IME_NAME,
            (empty(dataset_file) ? '' : "with dataset: " .. dataset_file),
        )
    catch
        echom printf("Failed to start %s: %s", IME_NAME, v:exception)
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
    echom IME_NAME "disabled"
enddef

def IMECleanup()
    if !empty(saved_mappings)
        RestoreMappings()
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

export def IMEPause()
    ime_enabled = false
    if !empty(saved_mappings)
        RestoreMappings()
    endif
    echom IME_NAME "paused"
enddef

execute printf('command! -nargs=? %sEnable call IMEEnable(<q-args>)', IME_NAME)
execute printf('command! %sDisable call IMEDisable()', IME_NAME)
execute printf('command! %sPause call IMEPause()', IME_NAME)

augroup IMEEnable
    autocmd!
    autocmd VimEnter * call IMEEnable()
augroup END

augroup IMECleanup
    autocmd!
    autocmd VimLeavePre * call IMEDisable()
augroup END
