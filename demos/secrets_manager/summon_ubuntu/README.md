# Summon Demo - Ubuntu/Linux

Quick demonstration of using Summon to inject Conjur secrets into a bash application.

## Quick Start

### 1. Install Summon and Conjur Provider

Run the setup script:

```bash
cd setup
sudo ./setup.sh
```

This automatically installs:
- Summon CLI
- Conjur provider

### 2. Configure Conjur Connection

Set your Conjur credentials:

```bash
export CONJUR_APPLIANCE_URL="https://your-conjur-instance.com"
export CONJUR_ACCOUNT="your-account"
export CONJUR_AUTHN_LOGIN="your-username"
export CONJUR_AUTHN_API_KEY="your-api-key"
```

Or use the helper script:

```bash
cd setup
./configure.sh
```

This will persist the variables to `~/.bashrc`.

### 3. Configure Secret Mappings

Edit `secrets.yml` to map environment variables to Conjur paths:

```yaml
SECRET1: !var path/to/your/secret1
SECRET2: !var path/to/your/secret2
SECRET3: !var path/to/your/secret3
```

### 4. Run the Demo

```bash
./demo.sh
```

## How It Works

1. **demo.sh** - Validates Conjur environment variables and calls Summon
2. **Summon** - Reads `secrets.yml` and fetches secrets from Conjur
3. **consumer.sh** - Receives secrets as environment variables and displays them

```
demo.sh → summon → Conjur API → consumer.sh
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

- `setup/setup.sh` - Automated installation script
- `setup/configure.sh` - Helper to set and persist environment variables
- `demo.sh` - Main demo script
- `consumer.sh` - Application that consumes the secrets
- `secrets.yml` - Secret mapping configuration

## Next Steps

- Modify `secrets.yml` for your application's secrets
- Integrate into your CI/CD pipeline
- Use in production: `summon -p summon-conjur bash your-app.sh`

## Documentation

- **Summon Docs**: https://cyberark.github.io/summon/
- **Conjur Provider**: https://github.com/cyberark/summon-conjur