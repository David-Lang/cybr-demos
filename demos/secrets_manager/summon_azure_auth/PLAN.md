# Summon Azure Auth Demo Plan

This file tracks the buildout for `demos/secrets_manager/summon_azure_auth`.

## Objective

Create a repo-standard Secrets Manager demo based on `summon_aws_auth` that runs on an Ubuntu VM in Azure. The demo uses Summon and `summon-conjur` to retrieve safe-backed secrets by authenticating with Azure managed identity through `authn-azure`, not a Conjur API key.

## Assumptions

- The demo runs on an Ubuntu VM hosted in Azure.
- The VM has a user-assigned managed identity attached.
- The CyberArk tenant may not already have an `authn-azure` service configured.
- Setup creates/configures `authn-azure/<service-id>` when needed.
- The authenticator uses the `apps` group convention.
- Cleanup removes demo workload and safe resources, but leaves the Azure authenticator service in place.

## Progress

- [x] Create `summon_azure_auth` directory from the AWS-auth demo pattern.
- [x] Add this progress plan.
- [x] Add Azure authenticator service policy using `provider-uri` and `apps`.
- [x] Add Azure workload policy with managed identity annotations.
- [x] Adapt setup orchestration and vault setup paths.
- [x] Adapt runtime demo script for Azure metadata and Summon cloud auth.
- [x] Adapt cleanup to preserve `authn-azure/<service-id>`.
- [x] Update README, setup, and validation documentation.
- [x] Run syntax checks locally.
- [ ] Test end-to-end in a fresh Azure Ubuntu lab.
- [ ] Record lab-specific fixes discovered during test.

## New Lab Test Checklist

- Fill `setup/vars.env` with Azure tenant, subscription, resource group, and user-assigned managed identity values.
- Confirm the VM can obtain an Azure managed identity token from IMDS.
- Run `bash setup.sh`.
- Run `source ./conjur_authn_azure.env`.
- Run `bash demo.sh`.
- Confirm `SECRET1`, `SECRET2`, and `SECRET3` print non-empty values.

## Known Test Risks

- A VM with multiple user-assigned identities may require `AZURE_CLIENT_ID` in `setup/vars.env`.
- If `summon-conjur` cannot select the intended managed identity from metadata, set `SUMMON_AZURE_FETCH_TOKEN="true"` to pass a short-lived IMDS token explicitly through `CONJUR_AUTHN_JWT_TOKEN`.
- CyberArk safe synchronization can lag; setup waits for the safe delegation group, but a slow tenant may still need a retry.
