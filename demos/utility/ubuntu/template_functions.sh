#!/bin/bash

resolve_template() {
    # $1 input_file, $2 output_file
    if [ $# -ne 2 ]; then
        echo "Usage: resolve_template input_file output_file"
        return 1
    fi
    input_file="$1"
    output_file="$2"
    printf "" > "$output_file"

    while IFS= read -r line; do
        # Use a regular expression to find Go lang style templates with dots
        # echo "$line"
        # Use [[:space:]] (not \s): macOS /bin/bash 3.2 ERE does not treat \s as whitespace.
        pattern='\{\{[[:space:]]*\.([A-Za-z][A-Za-z0-9_]*)[[:space:]]*\}\}'
        while [[ $line =~ $pattern ]]; do
            pattern_match=${BASH_REMATCH[0]}
            template_var=${BASH_REMATCH[1]}
            value="${!template_var}"
            # Replace the template with the environment variable value
            line="${line//$pattern_match/$value}"
        done
        # Append the modified line to the output file
        echo "$line" >> "$output_file"
    done < "$input_file"
}