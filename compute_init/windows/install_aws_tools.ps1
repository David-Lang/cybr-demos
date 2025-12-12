# Windows PowerShell (5.1) – from PSGallery
# -Force → suppresses “trust repository” & overwrite prompts
# -AllowClobber → avoids conflicts with other AWS modules
# -Confirm:$false → disables confirmation dialogs
# Takes ~minutes to run to completion
# NuGet provider re-requisite
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module -Name AWSPowerShell -Scope CurrentUser -Force -AllowClobber -Confirm:$false

Get-Module -ListAvailable -Name AWSPowerShell

## To connect to AWS
#$ak = "ACCESS_KEY"
#$sk = "SECRET_KEY"
#Set-AWSCredential -AccessKey $ak -SecretKey $sk -StoreAs "default"
#Set-DefaultAWSRegion -Region ca-central-1
#Set-AWSCredential -ProfileName default

## Confirm Access
# Get-STSCallerIdentity

## S3 Usage
#Get-S3Bucket
#Get-S3Object -BucketName 'my-bucket' -KeyPrefix 'path/to/folder/'

#function Get-S3File {
#    param([string]$Uri)
#    $u = [Uri]$Uri
#    $bucket = $u.Host
#    # decode the key to remove %20 etc.
#    $key = [System.Uri]::UnescapeDataString($u.AbsolutePath).TrimStart('/')
#    $file = Split-Path $key -Leaf
#    echo Read-S3Object -BucketName $bucket -Key $key -File $file
#    Read-S3Object -BucketName $bucket -Key $key -File $file
#}
#
#Get-S3File "s3://bucket_name/dir1/dir2/file_name"
#

