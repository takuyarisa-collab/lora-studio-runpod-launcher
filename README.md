# RunPod bootstrap

These scripts prepare a fresh Ubuntu-based RunPod ComfyUI Pod without changing
ComfyUI, downloading models, installing custom nodes, or storing credentials.
They support the common RunPod case where the shell user is `root` and `sudo`
is absent. A non-root user is supported when `sudo` is available.

## First Pod setup

Run the public, credential-free launcher from a fresh Pod:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/takuyarisa-collab/lora-studio-runpod-launcher/main/first-boot.sh)
```

The launcher is hosted in the separate public
[`lora-studio-runpod-launcher`](https://github.com/takuyarisa-collab/lora-studio-runpod-launcher)
repository so it is available before authentication. That repository contains
no secrets or private-repository credentials. Its script installs/verifies
curl, Git, wget, GitHub CLI, Node.js 20+, and the Codex standalone CLI. It then
pauses for manual GitHub browser authentication, clones this private repository
to `/workspace/lora-studio`, and hands off to
`runpod/scripts/bootstrap.sh`. GitHub credentials are handled by `gh`; never
pass a PAT as a script argument or paste one into a log. Inspect the public
script before running it if the Pod is handling sensitive data.

Set `LORA_STUDIO_PARENT` in the same command to override the default parent
directory when needed:

```bash
LORA_STUDIO_PARENT=/some/persistent/path bash <(curl -fsSL https://raw.githubusercontent.com/takuyarisa-collab/lora-studio-runpod-launcher/main/first-boot.sh)
```

Before PR #11 is merged, acceptance tests can fetch and check out its branch
without resetting an existing checkout:

```bash
LORA_STUDIO_REF=feature/runpod-bootstrap-phase-1-6 bash <(curl -fsSL https://raw.githubusercontent.com/takuyarisa-collab/lora-studio-runpod-launcher/main/first-boot.sh)
```

When `LORA_STUDIO_REF` is unset, a new clone stays on the repository default
branch and an existing clone stays on its current ref. When it is set, the
launcher refuses a dirty checkout, validates and fetches the requested ref, then
checks out the fetched commit in detached-HEAD mode. It never resets the checkout.

The script then starts `codex login --device-auth` when needed. Complete the
headless-friendly device flow in a browser on another machine; it never reads or
stores an API key. After authentication, the same
initial command launches Codex in `/workspace/lora-studio`. On an already authenticated
Pod, including a second execution, it skips the login flow and launches Codex directly.

The Codex installer used by both scripts is the official standalone installer:

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
```

## Subsequent setup and safe re-runs

If the repository already exists, run:

```bash
cd /workspace/lora-studio
./runpod/scripts/bootstrap.sh
./runpod/scripts/verify-environment.sh
```

Both setup scripts are idempotent: they verify satisfactory installed tools,
reuse an existing Git checkout, and refuse to overwrite a non-repository
`lora-studio` path. They do not pull/reset the repository. `bootstrap.sh` also
reports OS, architecture, disk space, and the ComfyUI instance found from the
running process or filesystem; it does not assume `/workspace/ComfyUI` or port
3001/8188.

`verify-environment.sh` is read-only. It reports runtime versions, GPU/VRAM,
disk mounts, the running ComfyUI process and listening port, Git commit, and
model/custom-node summaries. Its default-Python PyTorch report may say
"unavailable" when ComfyUI uses its own virtual environment; inspect the
reported ComfyUI process path in that case. Review the hostname before pasting
the report into a public issue.

## Persistence and shutdown

RunPod storage depends on the selected template and mounts. A directory named
`/workspace` is not proof of persistent storage; the verifier reports whether
it is a dedicated mount. Treat everything on a container-only disk as
disposable across Stop, Terminate, or Pod recreation.

Before ending work, commit and push source changes, scripts, documentation,
workflow JSON, manifests, and non-sensitive validation notes to GitHub. Do not
commit credentials, model/LoRA/VAE binaries, private generated images, tokens,
cookies, signed URLs, or Codex/GitHub authentication state.

## Common failures

- **Node 12/older Node:** the scripts install Node.js 20 when the detected major
  version is below 20.
- **`libnode-dev` conflict:** an old Ubuntu `libnode-dev` package is removed only
  when a Node.js upgrade is required, before installing the NodeSource package.
- **npm Codex optional dependency error:** do not repair it with another global
  npm install. These scripts use the official standalone Codex installer.
- **No `sudo`:** RunPod commonly runs as root, so no `sudo` is needed. A non-root
  shell without `sudo` stops with a clear error before privileged changes.
- **Private clone fails:** rerun `gh auth login --hostname github.com --web`, then
  rerun `first-boot.sh`; an existing valid checkout is preserved.

The scripts never update ComfyUI, install custom nodes, download models/LoRAs/
VAEs, invoke RunPod APIs, or perform billing operations.
