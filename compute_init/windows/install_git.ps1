# Chocolatey installation bootstrap
Set-ExecutionPolicy Bypass -Scope Process -Force
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install git
choco install git -y
$env:Path += ";C:\Program Files\Git\cmd"

[Environment]::SetEnvironmentVariable(
        "Path",
        $env:Path + ";C:\Program Files\Git\cmd",
        [EnvironmentVariableTarget]::Machine
)

git --version
