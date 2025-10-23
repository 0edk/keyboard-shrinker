# Roraer
"Roraer Dora" comes from "Programmer Dvorak" and the way that it filters letters, and is the name for a fuzzy input method designed for programming.

[Programmer Dvorak]( https://www.kaufmann.no/roland/dvorak/index.html ) (Kaufmann, 2000s) lays out letters the same as Dvorak, but rearranges symbols to put more common ones nearer to the middle.
Letters still take up enough space that symbols remain unergonomic, being pushed to the side.
We can do better.

Most code is a mix of numbers, symbols, and words taken from a well-defined set of identifiers.
You pick out such an identifier by typing letters.
Normally, you type every letter of a prefix long enough to auto-complete.
With Roraer, you type a subsequence of the identifier using only a specific set of letters.

If you pick out identifiers using only part of the alphabet, you can repurpose the keys that were used for the rest of the alphabet.
This gives space for symbols, conveniently closer to the middle.

## Setup
Roraer only works on Vim, for I use Vim.
Much of the logic is separated by IPC into a Zig program, which could be integrated with other editors.

1. Install [Zig]( https://ziglang.org/ ) compiler
2. Compile the accessory:
```sh
zig build-exe src/main.zig
```
3. Install the accessory:
```sh
mv main /usr/local/bin/roraer
```
4. Load the Vim plugin:
```vim
source path/to/roraer/roraer_main.vim
```
5. Set your keyboard layout to Dvorak (or suffer a bit)

## Usage
Roraer starts automatically on some files.
Check in `:messages`.
Use `:RoraerEnable` and `:RoraerDisable` to control it manually.
`:RoraerPause` disables Roraer, but keeps the session alive for reuse when next enabled.

Roraer overrides typing mechanics in Insert mode.
At any time, it has a (possibly empty) "query": a sequence of letters in its accepted subset.
Type a letter in the accepted subset (`ACDEILNORSTU`), and it's added to the query, updating the word before the cursor.
Type any symbol (space is a symbol), and the query is cleared, the matched word made permanent, and the symbol appears.

Some keys are mapped to Roraer-specific actions:
- Next and Prev change the word before the cursor to another identifier that matches the query.
- Lit reverts the layout to normal until the next symbol, to type in full a new identifier.
- Skip extends the query to fit its current match.
- Deter demotes the word before the cursor down the ranking of matches for the query.
- Bksp works like Backspace when the query is empty, but removes the last letter of the query if there is one.

All key-mappings are shown in `layout.txt`.

## Example
Let's type a Python program.
```python
def factorial(n):
    if n == 0:
        return 1
    else:
        return n * factorial(n - 1)

print(factorial(10))
```

| Keypress | Notes |
|----------|-------|
| d        |       |
| Space    | `def` is a keyword, matched immediately to `d` |
| Lit      | New function name |
| f, a, c, ... l | |
| (        | Finish function name |
| n        | Intending parameter `n` |
| Prev     | First match was `numpy`, want just the letter |
| ), :, Enter, Tab | |
| i        | Keyword `if` matches `i` |
| Space    |       |
| n        | Now `n` is higher-ranked than `numpy` |
| Space, =, =, Space, 0 | |
| :, Enter, Tab |  |
| r        | Matches `re` (module) |
| e, t	   | No longer `re` but keyword `return` |
| Space    | Confirm match |
| 1, Enter, Bksp | |
| e, l, s  | Unintended matches until `els` |
| :, Enter, Tab |  |
| r, e, t  | `re` is shorter, hence a better match for `r` than `return` |
| Space, n, Space | |
| *, a, c  | So far matches `__package__` |
| t        | `factorial`, defined here, matches `act` |
| (, n, Space, - | |
| Space, 1, ), Enter | |
| Bksp, Bksp, Enter | |
| r, i     | Built-in `print` matches |
| (, a, c, t | `factorial` again |
| (, 1, 0, ), ) |  |
