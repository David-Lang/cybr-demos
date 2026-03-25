#!/usr/bin/env bash

sudo apt update && sudo apt upgrade -y
sudo apt install ubuntu-desktop-minimal -y

sudo systemctl set-default graphical.target
sudo systemctl restart gdm3
systemctl get-default

# expect  graphical.target or reboot required
# sudo reboot

wget https://d1uj6qtbmh3dt5.cloudfront.net/NICE-GPG-KEY
sudo gpg --import NICE-GPG-KEY
rm NICE-GPG-KEY

wget https://d1uj6qtbmh3dt5.cloudfront.net/2024.0/Servers/nice-dcv-2024.0-18131-ubuntu2204-x86_64.tgz

tar -xvzf nice-dcv-*.tgz
cd nice-dcv-*
sudo apt install ./nice-dcv-server_*.deb ./nice-dcv-web-viewer_*.deb

# see what you actually extracted
ls -d nice-dcv-*/

# cd into the directory you just extracted (use the exact name you printed)
cd nice-dcv-2024.0-18131-ubuntu2204-x86_64

# sanity check the debs are here
ls -1 *.deb

# install from *this* directory
sudo apt update
sudo apt install -y ./nice-dcv-server_*.deb ./nice-dcv-web-viewer_*.deb



sudo systemctl enable --now dcvserver
sudo dcv create-session --type=virtual --owner ubuntu dcv-session

#sudo dcv close-session my-session


#TCP 8443
#Source: Your IP (not 0.0.0.0/0)
#
#From browser:
#https://<public-ip>:8443


sudo systemctl status dcvserver --no-pager
#sudo systemctl enable --now dcvserver

sudo dcv list-sessions
sudo dcv create-session --type=console --owner ubuntu my-session


# install Xorg + a lightweight desktop
sudo apt update
sudo apt install -y xorg xfce4 xfce4-goodies dbus-x11

# install nice-xdcv from your extracted folder
cd ~/nice-dcv-2024.0-18131-ubuntu2204-x86_64
sudo apt install -y ./nice-xdcv_*.deb

# set XFCE as the session for ubuntu
echo "xfce4-session" | sudo tee /home/ubuntu/.xsession >/dev/null
sudo chown ubuntu:ubuntu /home/ubuntu/.xsession

# restart DCV
sudo systemctl restart dcvserver



