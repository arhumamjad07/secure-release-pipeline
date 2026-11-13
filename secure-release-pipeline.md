# Secure Container Release Pipeline

## Objective

Build a portfolio project that takes a small FastAPI service from a Git commit to a running Kubernetes release. The cluster must accept an image only when its exact digest has verified build provenance from the approved repository and release workflow. Demonstrate a successful release, rejection of untrusted builds, and rollback to a previous approved release. This project should show practical Linux, CI/CD, infrastructure as code, and defensive security testing.

## Instructions for Codex

Inspect the repository and its instructions first. If it is empty, scaffold a minimal service. Implement one milestone at a time and run its checks before starting the next. Give me the commands, results, and a short explanation of what each stage proves. Record real results in the README. Identify any check you could not run and what access it needs. Use a project-owned test registry and cluster for all deployment tests.

## Stack

- Workload — Python, FastAPI and pytest. Use a small service with a health endpoint and a version response so a release or rollback can be observed.
- Build and release — GitHub Actions, Docker Buildx, GitHub Container Registry (GHCR), and GitHub build provenance attestations.
- Deployment — kind for local Kubernetes, Helm for the workload, and Sigstore Policy Controller for admission. Use the GitHub trust root and check the selected controller version's documented support for verifying GitHub attestations and matching the approved workflow.
- Cloud extension — Terraform, an Ubuntu VM running K3s, and a narrowly scoped GitHub Actions OIDC role if GitHub deploys AWS infrastructure.

## Build sequence

1. **Run locally.** Build the API and its tests. Package it in a non-root container. Verify the container starts and returns the expected version and health status. Add concise local setup commands.
2. **Publish one immutable artifact.** Run tests on pull requests. Use a separate release workflow triggered from the protected release branch or release environment. Build and publish the container, capture its SHA-256 digest, and generate GitHub build provenance for that exact digest. Document how to verify the provenance and identify the source commit and workflow. Scope workflow permissions by job. Keep pull request checks separate from publishing credentials.
3. **Enforce admission locally.** Create a kind cluster and a protected application namespace. Configure the controller to enforce verification there. Pin the expected issuer and exact repository, release workflow and approved ref as supported by the verified identity and claims. Deploy by digest through Helm. Confirm that missing provenance, an untrusted signer, and out-of-policy image references are denied within the protected namespace. Keep release permissions distinct from permission to change the admission policy. If the chosen controller cannot enforce these checks, document the gap and resolve it before claiming success.
4. **Test rollout and rollback.** Publish two approved releases with different version responses. Deploy each in turn, wait for readiness, and roll back to the first digest. Verify the running image and version after each operation. Keep the admission policy enabled throughout. Automate the checks that can run in CI and provide a repeatable script for any that need a configured registry or trusted release credentials.
5. **Deploy the same controls to the cloud.** Provision one Ubuntu VM with Terraform and install K3s. Reuse the Helm chart, verified digests and admission policy. Document access, estimated cost and teardown. Apply cloud changes once an AWS sandbox, credentials and a budget are available. Until then, validate Terraform and complete the local demonstration. A single VM is sufficient for this portfolio deployment.

## Acceptance tests

| Scenario | Expected result |
|---|---|
| Image built by the approved release workflow, deployed by its verified digest | Workload is admitted, becomes ready, and reports the expected version. |
| Project-owned test image with no attestation | Kubernetes admission denies it and reports a verification failure. |
| Project-owned test image attested by a separate, unapproved workflow | Kubernetes admission denies it even though it has valid provenance. Use a separate digest for this fixture. |
| Unapproved registry or an image reference outside the defined policy | Kubernetes admission denies it in the protected namespace. |
| Roll back from release B to previously verified release A | Release A becomes ready and reports its original version and digest. |

## Portfolio evidence

Keep the source, workflows, Helm chart, policy and Terraform in one repository. The README should explain how to reproduce the demo, what the trust policy checks, and what build provenance proves. Save the approved and rejected admission outputs and a short rollback transcript, with credentials and account details removed. Report the cloud milestone as complete only after a live deployment has been verified.

## First task

Start with milestones 1 and 2. Set up the FastAPI service, tests, Docker build and separate GitHub Actions workflows. Run the local checks. If no GitHub repository is connected yet, prepare the workflows and record the exact steps needed to verify the first real release.
