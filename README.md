# Secure release pipeline

A minimal FastAPI workload and separate pull request and trusted release workflows.
The complete project plan is in [secure-release-pipeline.md](secure-release-pipeline.md).
Milestone 1 works locally. Milestone 2 is implemented but still needs its first real
GitHub Actions release. Kubernetes admission, rollback and AWS are future milestones.

## Local development

Requires Python 3.12 and Docker with BuildKit/Buildx for container checks.

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install --require-hashes -r requirements-dev.txt
python -m pytest -q
APP_VERSION=local-dev python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

`GET /health` returns `{"status":"ok"}`. `GET /version` returns
`{"version":"local-dev"}` (or `dev` when `APP_VERSION` is unset). Stop the server
with Ctrl-C. The version is read at startup so a release or rollback is observable.

Runtime and development dependency locks include transitive pins and SHA-256 hashes.
To deliberately update them using Python 3.12:

```sh
python -m pip install pip-tools==7.5.2
PIP_TOOLS_CACHE_DIR=/tmp/secure-pip-tools pip-compile --generate-hashes --strip-extras -o requirements.txt requirements.in
PIP_TOOLS_CACHE_DIR=/tmp/secure-pip-tools pip-compile --generate-hashes --strip-extras -o requirements-dev.txt requirements-dev.in
```

## Container checks

```sh
docker build --build-arg APP_VERSION=local-check -t secure-release-pipeline:local .
scripts/smoke-container.sh secure-release-pipeline:local local-check
```

The smoke script starts an isolated container on a dynamically assigned loopback
port, checks both response bodies, verifies UID 10001, and removes the container.
It uses a read-only filesystem, drops capabilities and prevents privilege escalation.
The image has a Docker health check and excludes tests, Git metadata and local
configuration from its build context. Release builds bake in the source commit.

In a managed environment with an HTTPS inspection CA, supply the combined public
CA bundle as a BuildKit secret (verification stays enabled):

```sh
docker build --secret id=proxy_ca,src=/etc/ssl/certs/ca-certificates.crt \
  --build-arg APP_VERSION=local-check -t secure-release-pipeline:local .
```

The CA is used only during dependency installation and is not copied into layers.
The Python base image is a moving tag; the resulting release **digest**, not the
base tag or convenience release tag, is the artifact identity. This setup does not
claim byte-for-byte rebuild reproducibility or vulnerability scanning.

## GitHub Actions and the first trusted release

`ci.yml` runs Python tests and the container smoke check on pull requests and pushes
to `main`. It has only `contents: read`, no registry login and no publishing step.
Actions are pinned to full commit SHAs. Fork PR code must never be run through
`pull_request_target` with publishing credentials.

`release.yml` is manually dispatched from protected `main`. Its single release job
uses the `release` environment and grants only the job's required permissions:
`contents: read`, `packages: write`, `id-token: write`, `attestations: write`. It tests
before publishing, builds to the project-owned GHCR package, attests the exact
Buildx digest, verifies the attestation, then pulls and smoke-tests that digest.
The second build adds OCI source/revision labels; its published digest is the
subject verified and recorded in the job summary.

Before dispatching:

1. Merge this change and enable Actions. Protect `main` with required reviews and
   the `Pull request checks / test` status check. Restrict bypass permissions and
   protect workflow changes through repository review rules.
2. Create a GitHub environment named `release`, restrict deployment branches to
   protected `main`, and configure required reviewers where the plan supports it.
   Environment creation alone does not establish protection. The workflow also
   refuses unprotected refs via `github.ref_protected`.
3. Allow this repository's Actions token to write its GHCR package and generate
   attestations. Public repositories support artifact attestations on current
   GitHub plans; private/internal repositories require a supporting Enterprise
   Cloud plan. No long-lived registry token is needed in workflow secrets.
4. Run **Trusted release → Run workflow → main** and approve its environment.
   Confirm tests, smoke checks, push, attestation and verification all succeed.
   Copy the full `ghcr.io/arhumamjad07/secure-release-pipeline@sha256:...` reference
   and source SHA from the successful job summary. Tags are convenience pointers
   and can move; use the digest for verification and future deployments.
5. Independently verify the exact reference using a current GitHub CLI with
   `gh attestation verify` (the CLI preinstalled in this cloud machine is too old).
   Authenticate with read access to the repository/attestations and package as
   needed. Use values copied from the release, not a newly resolved branch tip:

```sh
IMAGE=ghcr.io/arhumamjad07/secure-release-pipeline
DIGEST=sha256:REPLACE_WITH_RELEASE_DIGEST
COMMIT=REPLACE_WITH_FULL_RELEASE_SOURCE_SHA
gh attestation verify "oci://${IMAGE}@${DIGEST}" \
  --repo arhumamjad07/secure-release-pipeline \
  --signer-workflow arhumamjad07/secure-release-pipeline/.github/workflows/release.yml \
  --source-ref refs/heads/main \
  --source-digest "$COMMIT" \
  --deny-self-hosted-runners
docker pull "${IMAGE}@${DIGEST}"
scripts/smoke-container.sh "${IMAGE}@${DIGEST}" "$COMMIT"
```

GitHub's verifier validates the signature/certificate and GitHub trust root. The
additional constraints select the repository, exact release workflow, approved ref,
source commit and hosted runner. Inspect its verified provenance output for the
subject digest and source identity. Provenance binds the artifact to an identified
build; it does not prove the code is safe. Local verification is not Kubernetes
admission enforcement: the controller and negative admission tests remain unbuilt.

## Recorded validation (2026-11-13)

| Command/check | Actual local result | What it proves |
| --- | --- | --- |
| `python -m pip install --require-hashes -r requirements-dev.txt` | Passed in Python 3.12 virtual environment | Locked dependencies install with hash verification |
| `.venv/bin/python -m pytest -q` | 4 passed | Health, release version, dev default and unknown route behavior |
| `actionlint` 1.7.7, `bash -n scripts/smoke-container.sh`, `git diff --check` | Passed | Workflow schema/expressions, shell syntax and whitespace checks |
| `.venv/bin/python -m pip check` | Passed | Installed dependency requirements are consistent |
| Docker build with CA secret and `APP_VERSION=local-check` | Passed | Runtime dependencies and service package build successfully |
| `scripts/smoke-container.sh secure-release-pipeline:local local-check` | Passed | Actual container serves expected health/version as UID 10001 with runtime restrictions |

Pytest emitted one upstream Starlette/AnyIO deprecation warning. An initial smoke
attempt exposed a startup connection reset; the script now retries transport
failures while still failing immediately on incorrect response bodies.

Still required in GitHub: run the PR workflow on a real PR, configure/verify branch
and environment protection, publish to GHCR, issue the OIDC-backed provenance,
verify the actual digest/commit/workflow claims, and smoke-test the pulled release.
These were **not run locally**. Git read access works; the cloud CLI's API token
was rejected, and local execution cannot mint GitHub Actions workload identity.
No publishing permission or protection settings have been assumed. No cluster,
cloud infrastructure, admission tests, rollback or deployment has been attempted.
