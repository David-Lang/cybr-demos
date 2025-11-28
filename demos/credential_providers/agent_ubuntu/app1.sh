#!/bin/bash
set -euo pipefail

app_id="cp_app1"
safe="cp_app1"
user_name="ssh-user-1"

/opt/CARKaim/sdk/clipasswordsdk GetPassword \
-p AppDescs.AppID=$app_id \
-p QueryFormat=2 \
-p Query="Safe=$safe;UserName=$user_name" \
-p Reason="CP from jumpbox demo" \
-o Password