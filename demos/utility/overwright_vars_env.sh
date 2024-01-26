#!/bin/bash
set -euo pipefail

##
## "$HOME/.cybr-demos/overwrite_vars_env" expected format
## full_path VAR_NAME NEW_VALUE
## /home/ubuntu/cybr-demos/demos/conjur_cloud/github.com/setup/vars.env JWT_CLAIM_IDENTITY D2avid-Lang
##

apply_env_file() {
    local file_path="$1"

    # Check if the path exists
    if [ -e "$file_path" ]; then
        # Check if the file is a regular file
        if [ -f "$file_path" ]; then

             # Read the file line by line, skip comments, and call set_env_variable for each line
             while IFS=' ' read -r path varname new_value; do
                 # Skip lines starting with #
                 if [[ "$path" != \#* && "$path" =~ [^[:space:]] ]]; then
                    set_env_variable "$path" "$varname" "$new_value"
                 fi
             done < "$file_path"

            echo "Environment variables applied from $file_path."
        else
            echo "Error: $file_path is not a regular file."
        fi
    else
        echo "Error: Path $file_path does not exist."
    fi
}

set_env_variable() {
    local path="$1"
    local var_name="$2"
    local new_value="$3"

    # Check if the path exists
    if [ -e "$path" ]; then
        # Check if the file is a regular file
        if [ -f "$path" ]; then
            # Use awk to find and replace the value
            awk -v var="$var_name" -v new_val="$new_value" -F= '$1 == var {OFS="="; $2=new_val} 1' "$path" > "$path.tmp" && mv "$path.tmp" "$path"
            echo "Updated $path: $var_name to $new_value"
        else
            echo "Error: $path is not a regular file."
        fi
    else
        echo "Error: Path $path does not exist."
    fi
}

apply_env_file "$HOME/.cybr-demos/overwrite_vars_env"
