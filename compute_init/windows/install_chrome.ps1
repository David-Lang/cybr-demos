mkdir c:\init
Invoke-WebRequest 'https://dl.google.com/chrome/install/375.126/chrome_installer.exe' -OutFile "c:\init\chrome_installer.exe"
Start-Process "c:\\init\chrome_installer.exe" -ArgumentList "/silent /install" -NoNewWindow -Wait -PassThru
start-sleep -s 2