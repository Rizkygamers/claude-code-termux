# Claude Code Android

Installer for Anthropic's official Claude Code on Termux (aarch64 Android).

## 🇬🇧 English

### Installation

Run the following commands in Termux:

```bash
# 1. Update and upgrade packages
pkg update && pkg upgrade -y

# 2. Install git
pkg install git

# 3. Clone the repository
git clone https://github.com/ferrumclaudepilgrim/claude-code-android.git

# 4. Enter the directory
cd claude-code-android

# 5. Run the installer
bash install.sh
```

### Usage

After installation, simply type:
```bash
claude
```

### Updating
The wrapper automatically checks for updates once per day. To force an immediate update check, run:
```bash
claude --update-now
```

---

## 🇮🇩 Bahasa Indonesia

### Instalasi

Jalankan perintah berikut di Termux:

```bash
# 1. Update dan upgrade paket
pkg update && pkg upgrade -y

# 2. Instal git
pkg install git

# 3. Clone repository
git clone https://github.com/ferrumclaudepilgrim/claude-code-android.git

# 4. Masuk ke direktori
cd claude-code-android

# 5. Jalankan installer
bash install.sh
```

### Penggunaan

Setelah instalasi selesai, cukup ketik:
```bash
claude
```

### Update
Wrapper akan otomatis mengecek update sekali sehari. Untuk memaksa cek update sekarang, jalankan:
```bash
claude --update-now
```
