# Claude Code Termux

Tool to run Anthropic's official Claude Code on Termux.

> **Important:** Please ensure you are using the version of Termux from **[F-Droid](https://f-droid.org/en/packages/com.termux/)**, as the Play Store version is deprecated.

## 🇬🇧 English

> **Note:** Claude Code is free to use. However, please be aware of
        potential usage limits when running it with Ollama.

### Installation

Run the following commands in Termux:

```bash
# 1. Update and upgrade packages
pkg update && pkg upgrade -y

# 2. Install git
pkg install git

# 3. Clone the repository
git clone https://github.com/Rizkygamers/claude-code-termux.git

# 4. Enter the directory
cd claude-code-termux

# 5. Run the installer
bash install.sh
```

### Configuration

Before running, configure your Anthropic API key:

```bash
# Set your API key
export ANTHROPIC_API_KEY='your-api-key-here'

# Alternatively, add it to your .model file to make it permanent:
echo "export ANTHROPIC_API_KEY='your-api-key-here'" >> .model
source .model
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

> **Catatan:** Claude Code gratis untuk digunakan. Namun, harap perhatikan
         adanya potensi limit penggunaan saat menjalankannya dengan Ollama.

### Instalasi

> **Penting:** Pastikan Anda menggunakan Termux versi **[F-Droid](https://f-droid.org/en/packages/com.termux/)**, karena versi Play Store sudah tidak didukung (*deprecated*).

Jalankan perintah berikut di Termux:

```bash
# 1. Update dan upgrade paket
pkg update && pkg upgrade -y

# 2. Instal git
pkg install git

# 3. Clone repository
git clone https://github.com/Rizkygamers/claude-code-termux.git

# 4. Masuk ke direktori
cd claude-code-termux

# 5. Jalankan installer
bash install.sh
```

### Konfigurasi

Sebelum menjalankan, konfigurasikan kunci API Anthropic Anda:

```bash
# Atur API key Anda
export ANTHROPIC_API_KEY='api-key-anda-disini'

# Atau, tambahkan ke .model agar permanen:
echo "export ANTHROPIC_API_KEY='api-key-anda-disini'" >> .model
source .model
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
