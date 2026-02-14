# Summon Demo - Windows PowerShell

Quick demonstration of using Summon to inject Conjur secrets into a PowerShell application.

## Quick Start

### 1. Install Summon and Conjur Provider

Run as Administrator:

```powershell
.\setup.ps1
```

This automatically installs:
- Summon CLI
- Conjur provider (built from source)
- Go (if needed)

After installation, restart PowerShell.

### 2. Configure Conjur Connection

Set your Conjur credentials:

```powershell
$env:CONJUR_APPLIANCE_URL = "https://your-conjur-instance.com"
$env:CONJUR_ACCOUNT = "your-account"
$env:CONJUR_AUTHN_LOGIN = "your-username"
$env:CONJUR_AUTHN_API_KEY = "your-api-key"
```

Or use the helper script with defaults:

```powershell
.\configure.ps1
```

### 3. Configure Secret Mappings

Edit `secrets.yml` to map environment variables to Conjur paths:

```yaml
SECRET1: !var path/to/your/secret1
SECRET2: !var path/to/your/secret2
SECRET3: !var path/to/your/secret3
```

### 4. Run the Demo

```powershell
.\demo.ps1
```

## How It Works

1. **demo.ps1** - Validates Conjur environment variables and calls Summon
2. **Summon** - Reads `secrets.yml` and fetches secrets from Conjur
3. **consumer.ps1** - Receives secrets as environment variables and displays them

```
demo.ps1 → summon → Conjur API → consumer.ps1
         ↑
    secrets.yml
```

## Expected Output

```
--- Variables Used ---
CONJUR_APPLIANCE_URL=https://your-conjur-instance.com
CONJUR_ACCOUNT=your-account
CONJUR_AUTHN_LOGIN=your-username

Env Variables
SECRET1: [secret value 1]
SECRET2: [secret value 2]
SECRET3: [secret value 3]
```

## Files

- `setup.ps1` - Automated installation script
- `configure.ps1` - Helper to set environment variables with defaults
- `demo.ps1` - Main demo script
- `consumer.ps1` - Application that consumes the secrets
- `secrets.yml` - Secret mapping configuration

## Next Steps

- Modify `secrets.yml` for your application's secrets
- Integrate into your CI/CD pipeline
- Use in production: `summon -p summon-conjur pwsh your-app.ps1`

## Documentation

- **Setup Guide**: See `SETUP.md` for detailed installation instructions
- **Summon Docs**: https://cyberark.github.io/summon/
- **Conjur Provider**: https://github.com/cyberark/summon-conjur