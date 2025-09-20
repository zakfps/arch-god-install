#!/bin/bash
set -e

# ===== Step 0: Minimum Disk Check =====
MIN_SIZE_GB=50
ROOT_SIZE=$(df --output=avail /mnt | tail -1)
ROOT_SIZE_GB=$(( ROOT_SIZE / 1024 / 1024 ))

if [ "$ROOT_SIZE_GB" -lt "$MIN_SIZE_GB" ]; then
    echo "❌ Not enough disk space. Root is ${ROOT_SIZE_GB}GB, need at least ${MIN_SIZE_GB}GB."
    exit 1
fi

# ===== Step 1: Redirect Temporary Directory =====
mkdir -p /mnt/var/tmp
export TMPDIR=/mnt/var/tmp

# ===== Step 2: Stage 1 - Base System =====
pacstrap /mnt base linux linux-firmware sudo vim nano zsh bash-completion git base-devel wget curl openssh

# ===== Step 3: Stage 2 - Networking =====
arch-chroot /mnt pacman -S --noconfirm networkmanager ufw fail2ban

# ===== Step 4: Stage 3 - Desktop Environment =====
arch-chroot /mnt pacman -S --noconfirm plasma kde-applications xorg xorg-xinit spectacle gwenview

# ===== Step 5: Stage 4 - Applications =====
arch-chroot /mnt pacman -S --noconfirm brave firefox libreoffice-fresh tmux neofetch fastfetch

# ===== Step 6: Dotfiles in /etc/skel =====
mkdir -p /mnt/etc/skel
cat <<'EOF' > /mnt/etc/skel/.bashrc
alias ll='ls -lah'
export EDITOR=nano
export PATH=$HOME/bin:$PATH
neofetch
EOF

cat <<'EOF' > /mnt/etc/skel/.zshrc
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)
source $ZSH/oh-my-zsh.sh
alias ll='ls -lah'
EOF

cat <<'EOF' > /mnt/etc/skel/.vimrc
set number
syntax on
set tabstop=4
set shiftwidth=4
set expandtab
set cursorline
EOF

cat <<'EOF' > /mnt/etc/skel/.gitconfig
[user]
    name = Your Name
    email = your.email@example.com
[core]
    editor = vim
[color]
    ui = auto
[alias]
    st = status
    co = checkout
    br = branch
EOF

# ===== Step 7: First-Boot Automation =====
cat <<'EOF' > /mnt/root/setup.sh
#!/bin/bash
systemctl enable NetworkManager
echo "nameserver 1.1.1.1" > /etc/resolv.conf

# Install yay from AUR
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm

# Enable WireGuard if config exists
if [ -f /etc/wireguard/wg0.conf ]; then
    systemctl enable wg-quick@wg0
fi

# Enable firewall & fail2ban
ufw enable
systemctl enable fail2ban

# Disable this service after first run
systemctl disable firstboot-setup.service

echo "✅ First boot setup complete!"
EOF
chmod +x /mnt/root/setup.sh

# ===== Step 8: First-Boot Systemd Service =====
cat <<'EOF' > /mnt/etc/systemd/system/firstboot-setup.service
[Unit]
Description=Run first boot setup
After=network.target

[Service]
Type=oneshot
ExecStart=/root/setup.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

ln -s /etc/systemd/system/firstboot-setup.service /mnt/etc/systemd/system/multi-user.target.wants/firstboot-setup.service

# ===== Step 9: Enable NetworkManager and SDDM =====
arch-chroot /mnt systemctl enable NetworkManager
arch-chroot /mnt systemctl enable sddm

echo "✅ Installation script finished. Reboot into your new system — everything will complete automatically on first boot."
