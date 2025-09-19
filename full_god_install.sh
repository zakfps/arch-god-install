#!/bin/bash

# ===============================
# ARCH GOD INSTALL SCRIPT - FINAL
# ===============================
# WARNING: Erases /dev/nvme0n1 completely!
# ===============================

# 0. Set variables
WIFI_SSID="YourSSID"
WIFI_PASS="YourPassword"
USERNAME="goduser"
ROOT_PASS="ChangeMe123!"
USER_PASS="ChangeMe123!"
DOTFILES_REPO="https://github.com/addy-dclxvi/i3-starterpack.git"

# 1. Update system clock
timedatectl set-ntp true

# 2. Partition NVMe and create EFI + root
sgdisk -Zo /dev/nvme0n1
sgdisk -n1:1MiB:+512MiB -t1:ef00 -c1:"EFI" /dev/nvme0n1
sgdisk -n2:0:0 -t2:8300 -c2:"LinuxRoot" /dev/nvme0n1

# 3. Format partitions
mkfs.fat -F32 /dev/nvme0n1p1
mkfs.ext4 /dev/nvme0n1p2

# 4. Mount partitions
mount /dev/nvme0n1p2 /mnt
mkdir -p /mnt/boot
mount /dev/nvme0n1p1 /mnt/boot

# 5. Install base system + networking
pacstrap /mnt base linux linux-firmware vim nano networkmanager sudo git base-devel wget curl zsh openssh

# 6. Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# 7. Chroot into the new system
arch-chroot /mnt /bin/bash << EOF

# -------------------------------
# Inside chroot
# -------------------------------

# Timezone
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
hwclock --systohc

# Locale
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname
echo "archgod" > /etc/hostname
cat <<EOT >> /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   archgod.localdomain archgod
EOT

# Root password
echo "root:$ROOT_PASS" | chpasswd

# Create user
useradd -m -G wheel,docker -s /bin/zsh $USERNAME
echo "$USERNAME:$USER_PASS" | chpasswd
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Set Zsh for root
chsh -s /bin/zsh root

# Enable NetworkManager
systemctl enable NetworkManager

# Auto-connect to Wi-Fi
nmcli radio wifi on
nmcli dev wifi connect "$WIFI_SSID" password "$WIFI_PASS"

# Install KDE Plasma + Xorg + apps
pacman -S --noconfirm plasma plasma-wayland-session kde-applications xorg xorg-xinit \
htop wget curl gwenview spectacle libreoffice-fresh brave firefox \
vlc mpv pinta qbittorrent thunderbird docker ufw fail2ban neofetch fastfetch \
clamav rkhunter chkrootkit apparmor haveged

# Enable SDDM (display manager)
systemctl enable sddm

# Enable firewall & fail2ban
systemctl enable ufw
ufw default deny incoming
ufw default allow outgoing
ufw enable
systemctl enable fail2ban

# Enable AppArmor & entropy
systemctl enable apparmor
systemctl enable haveged

# Install yay (AUR helper)
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm

# Install AUR apps
yay -S --noconfirm visual-studio-code-bin zoom google-chrome slack-bin oh-my-zsh-git

# Clone and apply dotfiles
sudo -u $USERNAME git clone $DOTFILES_REPO /home/$USERNAME/.dotfiles
cd /home/$USERNAME/.dotfiles
sudo -u $USERNAME cp -r .config /home/$USERNAME/
sudo -u $USERNAME cp -r .zshrc /home/$USERNAME/ || true
chown -R $USERNAME:$USERNAME /home/$USERNAME

# Setup oh-my-zsh for root and user
RUNZSH=no CHSH=no sh -c "\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || true
sudo -u $USERNAME RUNZSH=no CHSH=no sh -c "\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || true

# Install oh-my-zsh plugins
git clone https://github.com/zsh-users/zsh-autosuggestions /usr/share/oh-my-zsh/custom/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting /usr/share/oh-my-zsh/custom/plugins/zsh-syntax-highlighting
echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' >> /home/$USERNAME/.zshrc
echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' >> /root/.zshrc

# Disable root SSH login
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl enable sshd

# Setup automatic updates (system + AUR)
cat <<EOT > /etc/systemd/system/auto-update.service
[Unit]
Description=Automatic system and AUR update

[Service]
Type=oneshot
ExecStart=/usr/bin/bash -c "pacman -Syu --noconfirm && sudo -u $USERNAME yay -Syu --noconfirm"
EOT

cat <<EOT > /etc/systemd/system/auto-update.timer
[Unit]
Description=Run auto-update daily

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOT

systemctl enable auto-update.timer

# Install Docker & enable
systemctl enable docker
systemctl start docker

# Setup systemd-boot
bootctl --path=/boot install
cat <<EOT > /boot/loader/loader.conf
default arch
timeout 5
editor 0
EOT
PARTUUID=\$(blkid -s PARTUUID -o value /dev/nvme0n1p2)
cat <<EOT > /boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=PARTUUID=\$PARTUUID rw
EOT

EOF

# 8. Unmount & reboot
umount -R /mnt
reboot
