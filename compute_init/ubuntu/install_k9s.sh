#!/bin/bash

curl -s https://api.github.com/repos/derailed/k9s/releases/latest | grep browser_download_url | grep Linux_amd64.tar.gz | cut -d '"' -f 4 | wget -i -
tar -xzf k9s_Linux_amd64.tar.gz
sudo mv k9s /usr/local/bin/
sudo chmod +x /usr/local/bin/k9s
k9s version
