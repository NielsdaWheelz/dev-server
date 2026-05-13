# Dev Server Walkthrough

This walkthrough starts from a Mac with nothing configured and ends with a
Hetzner VPS reachable through Tailscale, ready for Cursor Remote SSH, GitHub
SSH, Docker, Codex, and Claude Code.

The setup this repo builds is:

```text
Mac/phone -> Tailscale -> dev-server-cpx11 -> tmux/Cursor/Codex/Claude/Docker/GitHub SSH
```

## 1. Install Local Tools On Mac

Install the local CLIs:

```bash
brew install hcloud gh
```

Install the Tailscale Mac app from:

```text
https://tailscale.com/download
```

Open Tailscale, sign in, and make sure it says connected.

## 2. Log Into GitHub CLI On Mac

```bash
gh auth login
```

Choose:

```text
GitHub.com
SSH
Login with a web browser
```

Verify:

```bash
gh auth status
```

## 3. Configure Hetzner CLI

Create a Hetzner Cloud API token in the Hetzner Cloud Console.

Then create a local `hcloud` context:

```bash
hcloud context create dev-server
hcloud context use dev-server
```

Verify:

```bash
hcloud context active
hcloud location list
```

## 4. Create Or Upload Your Mac SSH Key To Hetzner

If you do not already have a Mac SSH key:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "$(whoami)@$(hostname)-macbook"
```

Upload the public key to Hetzner:

```bash
hcloud ssh-key create \
  --name niels-macbook \
  --public-key-from-file ~/.ssh/id_ed25519.pub
```

If it already exists, this command may fail with a duplicate-name error. That is
fine. Check with:

```bash
hcloud ssh-key list
```

## 5. Clone This Repo

```bash
mkdir -p ~/Documents/code
cd ~/Documents/code
git clone https://github.com/NielsdaWheelz/dev-server.git
cd dev-server
```

## 6. Create The Dedicated GitHub SSH Key For The Server

This key belongs to the dev server, not your Mac. It lets the server clone and
push GitHub repos without forwarding your Mac SSH agent.

```bash
mkdir -p secrets
chmod 700 secrets
ssh-keygen -t ed25519 \
  -C "niels-dev-server-github" \
  -f secrets/id_ed25519_github \
  -N ""
chmod 600 secrets/id_ed25519_github
chmod 644 secrets/id_ed25519_github.pub
```

Add that public key to your GitHub account:

```bash
gh ssh-key add secrets/id_ed25519_github.pub \
  --title dev-server-cpx11 \
  --type authentication
```

## 7. Render The Cloud-Init File

The template is safe to commit. The rendered file is not, because it contains
the server's GitHub private key.

```bash
./render-cloud-init.sh
```

Verify the YAML parses:

```bash
ruby -e "require 'yaml'; YAML.load_file('cloud-init-devbox.yaml'); puts 'cloud-init yaml ok'"
```

## 8. Create The Hetzner Firewall

Create a firewall:

```bash
hcloud firewall create \
  --name dev-server-firewall \
  --label purpose=remote-dev
```

Temporarily allow public SSH for first boot and Tailscale enrollment:

```bash
hcloud firewall add-rule \
  --direction in \
  --protocol tcp \
  --port 22 \
  --source-ips 0.0.0.0/0 \
  --source-ips ::/0 \
  dev-server-firewall
```

Later, after Tailscale works, you will remove this rule.

## 9. Create The VPS

Create a `cpx11` in Hillsboro:

```bash
hcloud server create \
  --name dev-server-cpx11 \
  --type cpx11 \
  --image ubuntu-24.04 \
  --location hil \
  --ssh-key niels-macbook \
  --firewall dev-server-firewall \
  --enable-backup \
  --label purpose=remote-dev \
  --label environment=dev \
  --user-data-from-file ./cloud-init-devbox.yaml
```

Get the public IP:

```bash
hcloud server ip dev-server-cpx11
```

## 10. Add The Initial Mac SSH Alias

Edit your Mac SSH config:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
nano ~/.ssh/config
```

Add this, replacing `PUBLIC_IP_FROM_HCLOUD`:

```sshconfig
Host dev-server
  HostName PUBLIC_IP_FROM_HCLOUD
  User niels
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  ServerAliveInterval 30
  ServerAliveCountMax 4
  StrictHostKeyChecking accept-new
  ForwardAgent no
```

Fix permissions:

```bash
chmod 600 ~/.ssh/config
```

## 11. Wait For Bootstrap To Finish

```bash
ssh dev-server 'cloud-init status --wait'
```

If it reports an error, inspect:

```bash
ssh dev-server 'sudo tail -n 200 /var/log/cloud-init-output.log'
```

Verify the installed tools:

```bash
ssh dev-server 'cat /etc/devbox-bootstrap.log'
```

Expected tools include:

```text
Node
git
gh
tmux
Docker
Docker Compose
Tailscale
Codex CLI
Claude Code
```

## 12. Enter The Persistent Shell

```bash
ssh dev-server
tmux new -A -s main
```

Detach without killing the session:

```text
Ctrl-b then d
```

Reattach:

```bash
ssh dev-server
tmux attach -t main
```

## 13. Verify GitHub SSH From The Server

On the server:

```bash
ssh -T git@github.com
```

Expected result:

```text
Hi USERNAME! You've successfully authenticated, but GitHub does not provide shell access.
```

## 14. Log Into GitHub CLI On The Server

On the server:

```bash
gh auth login
```

Choose:

```text
GitHub.com
SSH
Login with a web browser
Skip uploading an SSH key
```

Verify:

```bash
gh auth status
```

## 15. Log Into Codex Subscriptions

This bootstrap routes Codex state by folder:

```text
~/src/work/...      -> ~/.codex-work
everything else    -> ~/.codex-personal
```

Load the shell helpers if you are in an existing shell:

```bash
source ~/.bash_aliases
```

Log into personal:

```bash
cd ~/src/personal
codex login --device-auth
codex login status
```

Log into work:

```bash
cd ~/src/work
codex login --device-auth
codex login status
```

Check which Codex home the current folder will use:

```bash
codex-home
```

You can also force one:

```bash
codex-personal login status
codex-work login status
```

## 16. Log Into Claude Code Subscriptions

This bootstrap routes Claude Code state by folder:

```text
~/src/work/...      -> ~/.claude-work
everything else    -> ~/.claude-personal
```

Load the shell helpers if you are in an existing shell:

```bash
source ~/.bash_aliases
```

Log into personal:

```bash
cd ~/src/personal
claude auth login
claude auth status
```

Log into work:

```bash
cd ~/src/work
claude auth login
claude auth status
```

Check which Claude config dir the current folder will use:

```bash
claude-home
```

You can also force one:

```bash
claude-personal auth status
claude-work auth status
```

## 17. Enroll The Server In Tailscale

On the server:

```bash
sudo tailscale up --ssh --hostname=dev-server-cpx11 --operator=niels
```

Open the printed login URL in your Mac browser and approve the server.

Get the server's Tailscale IP:

```bash
tailscale ip -4
```

From your Mac, test the Tailscale path:

```bash
ssh niels@TAILSCALE_IP_FROM_SERVER
```

## 18. Switch The Mac SSH Alias To Tailscale

Edit `~/.ssh/config` on your Mac.

Change `dev-server` to use the Tailscale IP, and keep a public break-glass alias:

```sshconfig
Host dev-server
  HostName TAILSCALE_IP_FROM_SERVER
  User niels
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  ServerAliveInterval 30
  ServerAliveCountMax 4
  StrictHostKeyChecking accept-new
  ForwardAgent no

Host dev-server-public
  HostName PUBLIC_IP_FROM_HCLOUD
  User niels
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
  ServerAliveInterval 30
  ServerAliveCountMax 4
  StrictHostKeyChecking accept-new
  ForwardAgent no
```

Verify:

```bash
ssh dev-server 'hostname; whoami; tailscale ip -4'
```

## 19. Close Public SSH

After `ssh dev-server` works through Tailscale, remove public SSH from the
Hetzner firewall:

```bash
hcloud firewall delete-rule \
  --direction in \
  --protocol tcp \
  --port 22 \
  --source-ips 0.0.0.0/0 \
  --source-ips ::/0 \
  dev-server-firewall
```

Verify the firewall has no public inbound rules:

```bash
hcloud firewall describe dev-server-firewall
```

Verify the public path is closed:

```bash
ssh -o ConnectTimeout=5 dev-server-public 'true'
```

That should time out or fail.

## 20. Connect Cursor

Install Cursor's Remote SSH extension if needed.

In Cursor:

```text
Cmd-Shift-P
Remote-SSH: Connect to Host
dev-server
```

Open:

```text
/home/niels/src/work
```

or:

```text
/home/niels/src/personal
```

## 21. Clone And Work

On the server:

```bash
cd ~/src/work
gh repo clone OWNER/REPO
cd REPO
codex
claude
docker compose up
```

Use `tmux` for long-running work:

```bash
tmux new -A -s repo-name
```

## 22. Connect From Android With Termux

Install the Tailscale Android app and connect to the same tailnet.

In Termux:

```bash
pkg update
pkg install openssh tmux
mkdir -p ~/.ssh
chmod 700 ~/.ssh
```

Create a Termux SSH alias:

```bash
cat > ~/.ssh/config <<'EOF'
Host dev-server
  HostName TAILSCALE_IP_FROM_SERVER
  User niels
  ServerAliveInterval 30
  ServerAliveCountMax 4
  StrictHostKeyChecking accept-new
EOF
chmod 600 ~/.ssh/config
```

Connect:

```bash
ssh dev-server
tmux attach -t main
```

In Termux, Volume Down acts as Ctrl. In nano, save with `Volume Down + O`,
press Enter, and exit with `Volume Down + X`.

## 23. Daily Use

From Mac:

```bash
ssh dev-server
tmux new -A -s main
```

Work folders:

```text
~/src/work
~/src/personal
```

Public SSH should stay closed. Keep Tailscale connected on the client device.

## 24. Rebuild Later

To rebuild from scratch:

```bash
cd ~/Documents/code/dev-server
./render-cloud-init.sh
hcloud server delete dev-server-cpx11
hcloud server create \
  --name dev-server-cpx11 \
  --type cpx11 \
  --image ubuntu-24.04 \
  --location hil \
  --ssh-key niels-macbook \
  --firewall dev-server-firewall \
  --enable-backup \
  --label purpose=remote-dev \
  --label environment=dev \
  --user-data-from-file ./cloud-init-devbox.yaml
```

After rebuild, repeat the human login steps for:

```text
gh
Codex personal/work
Claude Code personal/work
Tailscale
```

The dedicated GitHub SSH key is reused from `secrets/id_ed25519_github`, so you
do not need to add a new GitHub SSH key unless you regenerate it.
