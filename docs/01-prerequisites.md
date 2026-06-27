# Prerequisites

## Hardware
- Apple Silicon Mac (M1/M2/M3/M4)
- Minimum 16GB RAM
- Minimum 30GB free disk space (VMs use sparse allocation, actual usage ~11-14GB)

## Step 1 - Install Homebrew
Homebrew is a package manager for Mac. Install it first if not already installed.

    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

Verify:

    brew --version

## Step 2 - Install Mac Tools

    brew install lima kubectl helm k9s

| Tool    | Version | Purpose                            |
|---------|---------|------------------------------------|
| lima    | 2.1.3   | Creates Linux VMs on Apple Silicon |
| kubectl | 1.36.2  | Talks to Kubernetes cluster        |
| helm    | 4.2.2   | Package manager for Kubernetes     |
| k9s     | 0.51.0  | Live terminal dashboard            |

Verify each tool installed correctly:

    lima --version
    kubectl version --client
    helm version
    k9s version

## Step 3 - Configure Git

    git config --global user.name "Your Name"
    git config --global user.email "your@email.com"

Verify:

    git config --get user.name
    git config --get user.email

## Step 4 - Set up SSH key for GitHub
This avoids being asked for a password every time you push to GitHub.

Check if you already have a key:

    ls ~/.ssh

If id_ed25519 exists skip the generate step.

Generate a new key:

    ssh-keygen -t ed25519 -C "your@email.com"

Copy your public key:

    cat ~/.ssh/id_ed25519.pub

Add it to GitHub:
- Go to github.com
- Click profile picture -> Settings
- Left sidebar -> SSH and GPG keys
- Click New SSH key
- Paste your public key
- Click Add SSH key

Switch your repo from HTTPS to SSH:

    git remote set-url origin git@github.com:yourusername/repo.git

Test the connection:

    ssh -T git@github.com

Expected output:
    Hi yourusername! You've successfully authenticated

## Step 5 - Install socket_vmnet from source
Lima requires socket_vmnet in a root-only location.
Homebrew installation is rejected by Lima for security reasons because
Homebrew installs to a user-writable location which Lima considers insecure.
socket_vmnet runs as root and creates network interfaces so it must be
in a location only root can modify.

    git clone https://github.com/lima-vm/socket_vmnet.git
    cd socket_vmnet
    git checkout v1.2.2
    make
    sudo make PREFIX=/opt/socket_vmnet install.bin

Verify it installed to the correct location:

    ls /opt/socket_vmnet/bin/socket_vmnet

Set up sudoers so Lima can run socket_vmnet without password prompts:

    limactl sudoers > /tmp/lima-sudoers
    cat /tmp/lima-sudoers
    sudo install -o root /tmp/lima-sudoers /etc/sudoers.d/lima

Verify sudoers:

    cat /etc/sudoers.d/lima

## Step 6 - Verify disk space
Each VM uses sparse disk allocation so actual usage is much less than reserved.
Recommended minimum 30GB free before starting.

    df -h ~

## Notes on Memory
VMs reserve memory immediately when started unlike disk which is sparse.
Total VM memory usage with all 4 nodes running:

    control-plane    3.5GiB
    worker-1         2.0GiB
    worker-2         2.0GiB
    worker-3         3.0GiB
    Total            10.5GiB

Leave at least 3-4GiB for macOS itself.
Recommended to stop VMs when not in use:

    limactl stop --all
