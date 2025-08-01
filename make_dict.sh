#!/bin/sh
TITLE="$1"
shift
cat "$@" | grep -o '\S\+' | grep -v '^http' | \
    grep -o "[a-zA-Z]\([_'a-zA-Z]*[a-zA-Z]\)\?" | sort | uniq -c | \
    sort -rn >"dicts/${TITLE}_$(date '+%Y-%j')"
