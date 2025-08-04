#!/bin/sh
export PAGER=cat
for source_file in src/*
do
    if zig ast-check "$source_file"
    then
        if [ `wc -l <"$source_file"` -ge 200 ]
        then
            printf '%s is long\n' "$source_file"
        fi
        printf 'n\n' | dfdt "$source_file" zig fmt "$source_file"
        printf '\n'
    fi
done
