function Load-DotEnv {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "File not found: $Path"
    }

    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()

        # skip blanks and comments
        if ($line -eq "" -or $line.StartsWith("#")) { return }

        # split KEY=VALUE
        $parts = $line -split "=", 2
        if ($parts.Count -ne 2) { return }

        $key   = $parts[0].Trim()
        $value = $parts[1].Trim().Trim('"', "'")   # remove wrapping quotes
        Write-Host "$key=$value"

        # Export as environment variable
        #$env:${key} = $value

        # Export as PowerShell variable
        Set-Variable -Name $key -Value $value -Scope Script
    }
}