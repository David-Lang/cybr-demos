#!/bin/bash
# EC2 expected to have s3 access via its attached IAM Role

get_s3_asset() {
    # $1 = S3 URI, $2 = target path
    if [ $# -ne 2 ]; then
        echo "Usage: get_asset <s3://bucket/key> <local_target_path>"
        return 1
    fi

    s3_uri="$1"
    target_path="$2"

    # Validate S3 URI
    if [[ ! "$s3_uri" =~ ^s3://[^/]+/.+ ]]; then
        echo "Error: Invalid S3 URI: $s3_uri"
        return 1
    fi

    # Ensure AWS CLI uses instance profile, not config
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    unset AWS_PROFILE AWS_DEFAULT_PROFILE
    export AWS_SHARED_CREDENTIALS_FILE=/dev/null
    export AWS_CONFIG_FILE=/dev/null

    # Confirm identity
    echo "Using IAM Role identity:"
    aws sts get-caller-identity || return 1

    # Create local directory if needed
    dest_dir="$(dirname "$target_path")"
    if [ ! -d "$dest_dir" ]; then
        mkdir -p "$dest_dir" || {
            echo "Error: Unable to create directory $dest_dir"
            return 1
        }
    fi

    echo "Downloading $s3_uri → $target_path"
    aws s3 cp "$s3_uri" "$target_path"
}
