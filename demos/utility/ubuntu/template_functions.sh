#!/bin/bash

resolve_template() {
    # $1 input_file, $2 output_file
    if [ $# -ne 2 ]; then
        echo "Usage: resolve_template input_file output_file" >&2
        return 1
    fi
    local input_file="$1"
    local output_file="$2"

    if [ ! -f "$input_file" ]; then
        printf "ERROR: resolve_template: input file not found: %s\n" "$input_file" >&2
        return 1
    fi

    printf "" > "$output_file"

    local line pattern pattern_match template_var value
    # Go-style templates like {{ .VarName }}. Use [[:space:]] (POSIX) rather than
    # \s, which bash's ERE engine does not support (it silently fails to match
    # templates that contain whitespace).
    pattern='\{\{[[:space:]]*\.([A-Za-z][A-Za-z0-9_]*)[[:space:]]*\}\}'

    while IFS= read -r line || [ -n "$line" ]; do
        while [[ $line =~ $pattern ]]; do
            pattern_match="${BASH_REMATCH[0]}"
            template_var="${BASH_REMATCH[1]}"

            # Fail explicitly if the referenced variable is unset or empty,
            # rather than emitting a half-resolved file that breaks downstream.
            if [ -z "${!template_var+set}" ]; then
                printf "ERROR: resolve_template: variable '%s' referenced in %s is not set\n" \
                    "$template_var" "$input_file" >&2
                return 1
            fi
            value="${!template_var}"
            if [ -z "$value" ]; then
                printf "ERROR: resolve_template: variable '%s' referenced in %s is empty\n" \
                    "$template_var" "$input_file" >&2
                return 1
            fi

            line="${line//$pattern_match/$value}"
        done
        printf '%s\n' "$line" >> "$output_file"
    done < "$input_file"

    # Final guard: no unresolved templates may remain in the output.
    if grep -nE '\{\{[[:space:]]*\.' "$output_file" >/dev/null 2>&1; then
        printf "ERROR: resolve_template: unresolved templates remain in %s:\n" "$output_file" >&2
        grep -nE '\{\{' "$output_file" >&2
        return 1
    fi
}
