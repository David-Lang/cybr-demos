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
        pattern='\{\{\s*\.([A-Z][A-Z0-9_]*)\s*\}\}'
        while [[ $line =~ $pattern ]]; do
            pattern_match=${BASH_REMATCH[0]}
            echo "Found pattern: $pattern_match"
            template_var=${BASH_REMATCH[1]}
            echo "Variable: $template_var"
            value="${!template_var}"
            echo "Value: $value"
            # Replace the template with the environment variable value
            line="${line//$pattern_match/$value}"
        done
        # Append the modified line to the output file
        echo "$line" >> "$output_file"
    done < "$input_file"
}