# AWS EKS Helper Commands

This file is a helper reference for working with the AWS EKS variant of the Kubernetes demo.

Load the expected variables first:

```bash
region="$REGION"
eks_name="$EKS_NAME"
profile_name="$PROFILE_NAME"
eks_context="$EKS_CONTEXT"
```

## AWS CLI Profile

Configure and validate the AWS profile:

```bash
aws configure --profile "$profile_name"
aws sts get-caller-identity --profile "$profile_name"
```

## EKS Cluster Access

List clusters and update local kubeconfig:

```bash
aws eks list-clusters --region "$region" --profile "$profile_name"
aws eks update-kubeconfig --region "$region" --name "$eks_name" --profile "$profile_name"
```

## kubectl Context

Validate the Kubernetes context and cluster access:

```bash
kubectl config get-contexts
kubectl config use-context "$eks_context"
kubectl config current-context
kubectl config view
kubectl get namespaces
```

## EKS Auth Mapping

Inspect the AWS auth ConfigMap:

```bash
kubectl get configmap aws-auth -n kube-system -o yaml > aws-auth.yaml
kubectl get configmap aws-auth -n kube-system -o yaml
```

## AWS Network Inspection

Inspect AWS VPCs in the target region:

```bash
aws ec2 describe-vpcs --region "$region" --profile "$profile_name"
```

## Quick Recheck

Useful commands when debugging kubeconfig or context issues:

```bash
kubectl config view
kubectl config current-context
# kubectl config use-context <context-name>
```
