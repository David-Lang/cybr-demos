# DP Tenant Preparations

## Docs

<https://docs.cyberark.com/early-release/secure-ai-agents/content/secureai/introduction.htm>

## Roles

There are 2 roles:

1. **Secure AI Admins**
2. **Secure AI Builders**

If SAI was already installed on the tenant it won't have the "Secure AI Builders" role.
Re-install SAI **or** run this API:

```http
POST https://{identity-id}.id.cyberark.cloud/roles/storerole
```

```json
{
  "Name": "Secure AI Builders",
  "Description": "This role gives rights to Secure AI Gateway Builders"
}
```

> You can ask us for the Identity ID if needed.

## Create SIA MCP

SIA must be created via API only. Run:

```http
POST https://{tenant-name}-aigw.cyberark.cloud/api/targets/mcp-servers
Accept: application/x.targets.beta+json
```

```json
{
  "name": "SIA_DB_MCP_SERVER",
  "description": "SIA DB Mcp",
  "category": "DATABASES_AND_DATA_STORES",
  "source": {
    "type": "CUSTOM"
  },
  "upstream": {
    "url": "https://us-east-1-sia-db-mcp.adb.cyberark.cloud/mcp"
  },
  "authMethod": {
    "type": "OAUTH2.1"
  }
}
```

> `setup.sh` automates this when `SAI_AIGW_SIA_MCP_URL` is set in `vars.env`.

## MCP Inventory

Until the entry appears in the left sidebar under Administration, access the MCP inventory directly:

```
https://{tenant-name}.cyberark.cloud/adminportal/aigw/mcp/inventory
```

Example: <https://aigw-poc.cyberark.cloud/adminportal/aigw/mcp/inventory>

## MCP Servers for Testing

### Passthrough

| Server | URL |
|--------|-----|
| Context7 | `https://mcp.context7.com/mcp/oauth` |
| Snowflake | *(TBD)* |

### No Authentication (CyberArk as IDP)

| Server | URL | Auth |
|--------|-----|------|
| Context7 | `https://mcp.context7.com/mcp` | Choose "None" |

### SIA

Use the API above to create the SIA DB MCP server.

## Known Issues

- No "MCP servers" entry in the left sidebar.
- MCP Inventory filter doesn't work.
- Pre-defined list doesn't exist (coming soon).
- Context7 + OAuth in Claude AI (Desktop/Web) isn't working.
