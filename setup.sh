#!/usr/bin/env bash
# =============================================================================
#  POST-INSTALL SCRIPT — FEDORA 44 + HYPRLAND
#  Autor: personalizado para tu setup
#  Uso:   chmod +x post-install-fedora44.sh && sudo ./post-install-fedora44.sh
# =============================================================================

set -euo pipefail

# ── Colores ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${GREEN}[✔]${RESET} $*"; }
info() { echo -e "${CYAN}[→]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
die()  { echo -e "${RED}[✘]${RESET} $*"; exit 1; }

# ── Verificaciones ───────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && die "Ejecutá el script como root: sudo $0"
[[ -f /etc/fedora-release ]] || die "Este script es solo para Fedora."

REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo '')}"
[[ -z "$REAL_USER" ]] && die "No se pudo determinar el usuario real."
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# ══════════════════════════════════════════════════════════════════════════════
#  SECCIÓN 0 — IDENTIDAD DEL SISTEMA
# ══════════════════════════════════════════════════════════════════════════════
# ── Personalización ── EDITÁ ESTOS VALORES ───────────────────────────────────
PRETTY_HOSTNAME="Hyprion"          # Nombre bonito que muestra hostnamectl
STATIC_HOSTNAME="hyprion"          # Hostname de red (sin espacios ni mayúsculas)
PLYMOUTH_THEME="hypr-custom"       # Nombre del tema Plymouth a crear
GRUB_BG_PATH=""                    # Ruta a tu PNG para GRUB (dejá vacío para omitir)
#                                    Ej: "/home/usuario/wallpaper.png"
PLYMOUTH_IMG_PATH=""               # Ruta a tu PNG/SVG para Plymouth (opcional)
#                                    Ej: "/home/usuario/logo.png"
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║    POST-INSTALL FEDORA 44 + HYPRLAND                ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# ══════════════════════════════════════════════════════════════════════════════
#  SECCIÓN 1 — OPTIMIZACIÓN DNF
# ══════════════════════════════════════════════════════════════════════════════
info "Optimizando DNF..."
cat >> /etc/dnf/dnf.conf <<'EOF'
max_parallel_downloads=10
fastestmirror=True
defaultyes=True
keepcache=False
EOF
log "DNF optimizado"

# ══════════════════════════════════════════════════════════════════════════════
#  SECCIÓN 2 — REPOSITORIOS
# ══════════════════════════════════════════════════════════════════════════════
info "Habilitando RPM Fusion (free + nonfree)..."
dnf install -y \
  "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
  "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

info "Habilitando Flathub..."
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

info "Habilitando COPR de Hyprland (si el paquete no está en repos oficiales)..."
# En Fedora 44, Hyprland suele estar en repos; descomentá si hace falta:
# dnf copr enable -y solopasha/hyprland

log "Repositorios configurados"

# ══════════════════════════════════════════════════════════════════════════════
#  SECCIÓN 3 — ACTUALIZACIÓN BASE
# ══════════════════════════════════════════════════════════════════════════════
info "Actualizando el sistema..."
dnf upgrade -y --refresh
log "Sistema actualizado"

# ══════════════════════════════════════════════════════════════════════════════
#  SECCIÓN 3.5 — DRIVERS: AMD GPU + ROCm + WiFi INTEL
# ══════════════════════════════════════════════════════════════════════════════
info "Instalando drivers AMD (GPU + ROCm) y WiFi Intel..."

# ── Mesa / Vulkan AMD (RADV) ──────────────────────────────────────────────────
# mesa-dri-drivers incluye el driver de kernel AMDGPU y el driver Gallium
# Para Wayland/Hyprland se necesita mesa-vulkan-drivers (RADV = Vulkan AMD open)
DNF_AMD=(
  mesa-dri-drivers              # Driver OpenGL AMDGPU (Gallium3D)
  mesa-vulkan-drivers           # RADV: driver Vulkan AMD (open source, recomendado sobre AMDVLK)
  mesa-va-drivers               # VA-API: decodificación de video por hardware (AMD)
  mesa-vdpau-drivers            # VDPAU: soporte alternativo para video hardware
  libva                         # VA-API runtime
  libva-utils                   # vainfo — para verificar VA-API
  vulkan-tools                  # vulkaninfo — para verificar Vulkan
  vulkan-loader                 # Loader de Vulkan (necesario en runtime)
  libdrm                        # Direct Rendering Manager userspace
  xorg-x11-drv-amdgpu           # Driver Xorg AMD (útil para XWayland)

  # Firmware AMD (microcódigo GPU — crítico para estabilidad)
  linux-firmware                # Incluye amdgpu firmware
)
dnf install -y "${DNF_AMD[@]}"
log "Drivers AMD instalados"

# ── ROCm (compute GPU AMD — OpenCL, HIP, machine learning) ───────────────────
# ROCm tiene su propio repositorio oficial para Fedora
info "Habilitando repositorio ROCm..."
cat > /etc/yum.repos.d/rocm.repo <<'ROCMREPO'
[ROCm-latest]
name=ROCm Latest
baseurl=https://repo.radeon.com/rocm/rhel9/latest/main
enabled=1
priority=50
gpgcheck=1
gpgkey=https://repo.radeon.com/rocm/rocm.gpg.key
ROCMREPO

dnf makecache --repo=ROCm-latest

DNF_ROCM=(
  rocm-opencl                   # ROCm OpenCL runtime (corre shaders/compute en GPU AMD)
  rocm-opencl-devel             # Headers OpenCL
  rocm-hip-runtime              # HIP: plataforma de compute AMD (equivalente a CUDA)
  rocm-hip-devel                # Headers HIP
  rocminfo                      # Herramienta para verificar ROCm
  clinfo                        # Información de dispositivos OpenCL
  hipblaslt                     # BLAS acelerado por GPU (usado por PyTorch/ML)
)
dnf install -y "${DNF_ROCM[@]}" || \
  warn "Algunos paquetes ROCm no se pudieron instalar. Verificá compatibilidad con tu GPU en: https://rocm.docs.amd.com/en/latest/compatibility/compatibility-matrix.html"

# Agregar el usuario al grupo 'render' y 'video' (requerido para acceso ROCm/GPU)
usermod -aG render,video "$REAL_USER"
log "Usuario $REAL_USER agregado a grupos render y video (necesario para ROCm)"

# Variable de entorno ROCm
grep -q 'HSA_OVERRIDE_GFX_VERSION' /etc/environment || \
  echo '# ROCm — descomentá y ajustá si tu GPU no es detectada automáticamente' >> /etc/environment
echo '# HSA_OVERRIDE_GFX_VERSION=11.0.0' >> /etc/environment  # Ej para RX 7xxx
echo 'ROC_ENABLE_PRE_VEGA=1' >> /etc/environment               # Compatibilidad GPUs antiguas (Polaris/Vega)

log "ROCm instalado"

# ── WiFi Intel (iwlwifi) ──────────────────────────────────────────────────────
# El driver iwlwifi ya viene en el kernel de Fedora, pero necesita firmware
# y herramientas de gestión de red
info "Instalando soporte WiFi Intel..."

DNF_WIFI=(
  linux-firmware                # Firmware iwlwifi (si no fue instalado ya arriba)
  iwl7260-firmware              # Serie 7000
  iwl8000c-firmware             # Serie 8000/8260/8265
  iwlax210-firmware             # AX200/AX201/AX210/AX211 (WiFi 6/6E)
  NetworkManager                # Gestor de red (generalmente ya instalado)
  NetworkManager-wifi           # Plugin WiFi para NetworkManager
  NetworkManager-tui            # nmtui — interfaz TUI para configurar red
  iw                            # Herramienta CLI para WiFi (iw list, iw dev)
  wireless-tools                # iwconfig, iwlist (legacy pero útil)
  wpa_supplicant                # Backend de autenticación WPA/WPA2/WPA3
  rfkill                        # Gestión de radio (habilitar/deshabilitar WiFi/BT)
)
dnf install -y "${DNF_WIFI[@]}"

# Habilitar y arrancar NetworkManager si no está activo
systemctl enable --now NetworkManager
log "WiFi Intel instalado — driver iwlwifi activo en kernel Fedora"

# ── Bluetooth (Intel también maneja BT en muchas tarjetas) ───────────────────
info "Instalando soporte Bluetooth..."
dnf install -y \
  bluez \
  bluez-tools \
  bluez-cups \
  blueman

systemctl enable --now bluetooth
log "Bluetooth habilitado"
# ══════════════════════════════════════════════════════════════════════════════
# ══════════════════════════════════════════════════════════════════════════════
#  SECCIÓN 4 — HYPRLAND Y COMPONENTES WAYLAND

DNF_HYPRLAND=(
  # ── Core Hyprland ──────────────────────────────────────────────────────
  hyprland                    # El compositor
  hyprland-devel              # Headers (opcional, para plugins)
  xdg-desktop-portal-hyprland # Portal Wayland para screensharing, file picker
  xdg-desktop-portal-gtk      # Fallback para GTK apps

  # ── Barra de estado ────────────────────────────────────────────────────
  waybar                      # Barra altamente configurable
  waybar-config               # Configs de ejemplo

  # ── Lanzadores y menus ────────────────────────────────────────────────
  wofi                        # Lanzador Wayland
  fuzzel                      # Alternativa minimalista a rofi

  # ── Terminal ──────────────────────────────────────────────────────────
  kitty                       # Terminal GPU-accelerated
  foot                        # Terminal minimalista Wayland-nativa

  # ── Notificaciones ────────────────────────────────────────────────────
  mako                        # Daemon de notificaciones Wayland
  libnotify                   # notify-send y libs

  # ── Gestión de sesión / lock ──────────────────────────────────────────
  swaylock                    # Bloqueo de pantalla
  swayidle                    # Manejo de idle / suspensión

  # ── Portapapeles ──────────────────────────────────────────────────────
  wl-clipboard                # wl-copy / wl-paste
  cliphist                    # Historial de clipboard

  # ── Screenshots ───────────────────────────────────────────────────────
  grim                        # Screenshot completo
  slurp                       # Selección de región
  swappy                      # Anotaciones sobre screenshots

  # ── Wallpaper ─────────────────────────────────────────────────────────
  swaybg                      # Wallpaper estático
  hyprpaper                   # Wallpaper nativo de Hyprland

  # ── Polkit / Auth ─────────────────────────────────────────────────────
  polkit-gnome                # Agente de autenticación GTK

  # ── Themes GTK + íconos ───────────────────────────────────────────────
  adwaita-gtk2-theme
  papirus-icon-theme
  gnome-themes-extra

  # ── Fonts esenciales ──────────────────────────────────────────────────
  nerd-fonts                  # Necesario para íconos en Waybar, etc.
  fontawesome-fonts
  google-noto-emoji-fonts
)

dnf install -y "${DNF_HYPRLAND[@]}"
log "Hyprland y entorno Wayland instalados"

# ══════════════════════════════════════════════════════════════════════════════
#  SECCIÓN 5 — HERRAMIENTAS DE DESARROLLO
# ══════════════════════════════════════════════════════════════════════════════
info "Instalando herramientas de desarrollo..."

DNF_DEV=(
  # ── Shell ─────────────────────────────────────────────────────────────
  zsh
  zsh-autosuggestions
  zsh-syntax-highlighting

  # ── Editores ──────────────────────────────────────────────────────────
  neovim
  helix                       # Editor modal moderno, alternativa a neovim

  # ── Git y control de versiones ────────────────────────────────────────
  git
  git-delta                   # Diff mejorado para git
  lazygit                     # TUI para git
  gh                          # GitHub CLI

  # ── Utilidades de terminal ────────────────────────────────────────────
  tmux
  zellij                      # Multiplexor moderno, alternativa a tmux
  starship                    # Prompt cross-shell
  eza                         # ls moderno (reemplaza exa)
  bat                         # cat con syntax highlighting
  fd-find                     # find moderno
  ripgrep                     # grep ultrarrápido
  fzf                         # Fuzzy finder
  zoxide                      # cd inteligente
  btop                        # Monitor de recursos moderno
  dust                        # du moderno
  procs                       # ps moderno
  tokei                       # Contador de líneas de código

  # ── Compiladores y lenguajes ──────────────────────────────────────────
  gcc
  g++
  make
  cmake
  python3
  python3-pip
  python3-virtualenv
  nodejs
  npm
  rustup                      # Gestor de Rust

  # ── Contenedores ──────────────────────────────────────────────────────
  podman
  podman-compose
  buildah

  # ── Misc dev ──────────────────────────────────────────────────────────
  jq                          # Procesador JSON
  yq                          # Procesador YAML
  httpie                      # HTTP client CLI
  curl
  wget
  unzip
  p7zip
  stow                        # Gestor de dotfiles (symlinks)
)

dnf install -y "${DNF_DEV[@]}"

# Cambiar shell por defecto a zsh para el usuario
chsh -s "$(which zsh)" "$REAL_USER"
log "Herramientas de desarrollo instaladas; zsh seteado como shell por defecto"

# ══════════════════════════════════════════════════════════════════════════════
#  SECCIÓN 6 — MULTIMEDIA
# ══════════════════════════════════════════════════════════════════════════════
info "Instalando paquetes multimedia..."

# Codecs (requiere RPM Fusion)
dnf install -y \
  gstreamer1-plugins-{bad-free,bad-free-extras,ugly,good,base} \
  gstreamer1-libav \
  ffmpeg \
  ffmpeg-libs \
  libavcodec-freeworld

DNF_MULTIMEDIA=(
  mpv                         # Reproductor de video
  vlc                         # Reproductor alternativo
  celluloid                   # Frontend GTK para mpv
  obs-studio                  # Grabación y streaming
  kdenlive                    # Editor de video
  gimp                        # Editor de imágenes
  inkscape                    # Editor vectorial
  krita                       # Pintura digital
  imagemagick                 # Procesamiento de imágenes CLI
  ffmpegthumbnailer           # Thumbnails de video en el file manager
  pipewire
  pipewire-alsa
  pipewire-pulseaudio
  wireplumber
  pavucontrol                 # Control de volumen PipeWire/PulseAudio
  easyeffects                 # Efectos de audio
)

dnf install -y "${DNF_MULTIMEDIA[@]}"
log "Multimedia instalado"

# ══════════════════════════════════════════════════════════════════════════════
#  SECCIÓN 7 — GAMING
# ══════════════════════════════════════════════════════════════════════════════
info "Instalando paquetes de gaming..."

# Habilitar soporte de 32 bits para Steam
dnf install -y glibc.i686 libgcc.i686

DNF_GAMING=(
  steam
  wine
  winetricks
  lutris                      # Gestor de juegos
)

dnf install -y "${DNF_GAMING[@]}"

# ProtonPlus vía Flatpak (es la forma más actualizada)
info "Instalando ProtonPlus via Flatpak..."
flatpak install -y flathub com.vysp3r.ProtonPlus

log "Gaming instalado"

# ══════════════════════════════════════════════════════════════════════════════
#  SECCIÓN 8 — DISEÑO / IMPRESIÓN 3D / CAD
# ══════════════════════════════════════════════════════════════════════════════
info "Instalando herramientas de diseño 3D e impresión..."

# FreeCAD desde DNF
dnf install -y freecad

info "Instalando OrcaSlicer y Lychee Slicer via Flatpak..."
flatpak install -y flathub \
  com.softfever3d.orca-slicer \
  com.chitubox.LycheeSlicer

log "Herramientas 3D instaladas"

# ══════════════════════════════════════════════════════════════════════════════
#  SECCIÓN 9 — PRODUCTIVIDAD Y UTILIDADES
# ══════════════════════════════════════════════════════════════════════════════
info "Instalando apps de productividad..."

DNF_PRODUCTIVITY=(
  nautilus                    # File manager GNOME (usado en Wayland sin problema)
  nautilus-extensions         # API para extensiones de Nautilus
  file-roller                 # Gestor de archivos comprimidos integrado con Nautilus
  gvfs                        # Montaje automático
  gvfs-mtp                    # Android MTP
  network-manager-applet      # Applet de red para Waybar
  blueman                     # Gestor Bluetooth
  brightnessctl               # Control de brillo
  gammastep                   # Night mode / redshift Wayland
  nwg-look                    # Configurar tema GTK en entornos Wayland
  qt5ct                       # Configurar tema Qt
  qt6ct
)

dnf install -y "${DNF_PRODUCTIVITY[@]}"

# Flatpaks de productividad
info "Instalando Flatpaks de productividad..."
flatpak install -y flathub \
  md.obsidian.Obsidian \
  com.spotify.Client \
  com.mattjakeman.ExtensionManager \
  com.github.tchx84.Flatseal \
  org.gnome.Boxes \
  com.valvesoftware.Steam   # Por si no querés el RPM de Steam, tenés opción Flatpak

log "Productividad instalada"

# ══════════════════════════════════════════════════════════════════════════════
#  SECCIÓN 10 — IDENTIDAD DEL SISTEMA: HOSTNAME
# ══════════════════════════════════════════════════════════════════════════════
info "Configurando identidad del sistema..."

hostnamectl set-hostname "$STATIC_HOSTNAME"
hostnamectl set-pretty-hostname "$PRETTY_HOSTNAME"
hostnamectl set-chassis desktop      # o laptop, server, etc.
hostnamectl set-icon-name "computer" # Ícono en interfaces de red

log "Hostname seteado: $PRETTY_HOSTNAME ($STATIC_HOSTNAME)"

# ══════════════════════════════════════════════════════════════════════════════
#  SECCIÓN 11 — PLYMOUTH: TEMA DE BOOTEO
# ══════════════════════════════════════════════════════════════════════════════
info "Configurando Plymouth..."

dnf install -y plymouth plymouth-system-theme

THEME_DIR="/usr/share/plymouth/themes/${PLYMOUTH_THEME}"
mkdir -p "$THEME_DIR"

# ── Crear theme .plymouth ─────────────────────────────────────────────────────
cat > "${THEME_DIR}/${PLYMOUTH_THEME}.plymouth" <<EOF
[Plymouth Theme]
Name=${PLYMOUTH_THEME}
Description=Custom Hyprland boot theme
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/${PLYMOUTH_THEME}
ScriptFile=/usr/share/plymouth/themes/${PLYMOUTH_THEME}/${PLYMOUTH_THEME}.script
EOF

# ── Si se proveyó una imagen personalizada, copiarla ─────────────────────────
if [[ -n "$PLYMOUTH_IMG_PATH" && -f "$PLYMOUTH_IMG_PATH" ]]; then
  cp "$PLYMOUTH_IMG_PATH" "${THEME_DIR}/logo.png"
  LOGO_FILE="logo.png"
  info "Imagen Plymouth copiada desde $PLYMOUTH_IMG_PATH"
else
  warn "No se especificó PLYMOUTH_IMG_PATH. Se usará tema de texto/progreso."
  LOGO_FILE=""
fi

# ── Script Plymouth ───────────────────────────────────────────────────────────
# Este script define la animación de booteo.
# Si hay logo, lo muestra centrado con fade-in. Si no, muestra barra de progreso.
cat > "${THEME_DIR}/${PLYMOUTH_THEME}.script" <<'PLYSCRIPT'
// ── Fondo ────────────────────────────────────────────────────────────────────
background.SetColor(0.05, 0.05, 0.08, 1.0);  // Fondo casi negro azulado

Window.SetBackgroundTopColor(0.05, 0.05, 0.08);
Window.SetBackgroundBottomColor(0.02, 0.02, 0.05);

// ── Logo ─────────────────────────────────────────────────────────────────────
logo_image = Image("logo.png");

if (logo_image) {
    logo = Sprite(logo_image);
    logo.SetX(Window.GetWidth()  / 2 - logo_image.GetWidth()  / 2);
    logo.SetY(Window.GetHeight() / 2 - logo_image.GetHeight() / 2 - 40);
    logo.SetOpacity(0);

    // Fade-in suave
    progress = 0;
    fun fade_in_callback() {
        progress += 0.03;
        if (progress > 1.0) progress = 1.0;
        logo.SetOpacity(progress);
    }
    Plymouth.SetRefreshFunction(fade_in_callback);
}

// ── Barra de progreso ─────────────────────────────────────────────────────────
bar_width  = 300;
bar_height = 4;
bar_x      = Window.GetWidth()  / 2 - bar_width / 2;
bar_y      = Window.GetHeight() / 2 + 80;

// Fondo de la barra
bar_bg_img = Image.New(bar_width, bar_height);
bar_bg_img.Rectangle(0, 0, bar_width, bar_height, 0.15, 0.15, 0.18, 1.0);
bar_bg = Sprite(bar_bg_img);
bar_bg.SetX(bar_x);
bar_bg.SetY(bar_y);

// Barra de progreso activa
bar_img = Image.New(1, bar_height);
bar_img.Rectangle(0, 0, 1, bar_height, 0.4, 0.8, 1.0, 1.0); // azul-cyan
bar_sprite = Sprite(bar_img);
bar_sprite.SetX(bar_x);
bar_sprite.SetY(bar_y);
bar_sprite.SetScale(0, 1);

fun boot_progress_callback(duration, progress) {
    bar_sprite.SetScale(bar_width * progress, 1);
}
Plymouth.SetBootProgressFunction(boot_progress_callback);

// ── Mensaje de boot ───────────────────────────────────────────────────────────
message_sprite = Sprite();
message_sprite.SetX(20);
message_sprite.SetY(Window.GetHeight() - 30);

fun display_message_callback(text) {
    msg_img = Image.Text(text, 0.6, 0.6, 0.65);
    message_sprite.SetImage(msg_img);
}
Plymouth.SetDisplayMessageFunction(display_message_callback);

fun hide_message_callback(text) {
    message_sprite.SetImage(Image.New(1, 1));
}
Plymouth.SetHideMessageFunction(hide_message_callback);

PLYSCRIPT

# Si no hay imagen, reemplazar sección del logo por texto
if [[ -z "$LOGO_FILE" ]]; then
  # Insertar texto en lugar de logo en el script
  cat > "${THEME_DIR}/${PLYMOUTH_THEME}.script" <<'PLYSCRIPT_TEXT'
Window.SetBackgroundTopColor(0.05, 0.05, 0.08);
Window.SetBackgroundBottomColor(0.02, 0.02, 0.05);

// Título de texto
title_img = Image.Text("  [ HYPRION ]  ", 0.4, 0.8, 1.0, 1, "Sans Bold 24");
title = Sprite(title_img);
title.SetX(Window.GetWidth()  / 2 - title_img.GetWidth()  / 2);
title.SetY(Window.GetHeight() / 2 - 60);

// Subtítulo
sub_img = Image.Text("Fedora Linux", 0.5, 0.5, 0.6, 1, "Sans 12");
sub = Sprite(sub_img);
sub.SetX(Window.GetWidth() / 2 - sub_img.GetWidth() / 2);
sub.SetY(Window.GetHeight() / 2 - 20);

// Barra de progreso
bar_width  = 300;
bar_height = 3;
bar_x      = Window.GetWidth()  / 2 - bar_width / 2;
bar_y      = Window.GetHeight() / 2 + 40;

bar_bg_img = Image.New(bar_width, bar_height);
bar_bg_img.Rectangle(0, 0, bar_width, bar_height, 0.15, 0.15, 0.18, 1.0);
bar_bg = Sprite(bar_bg_img);
bar_bg.SetX(bar_x);
bar_bg.SetY(bar_y);

bar_img = Image.New(1, bar_height);
bar_img.Rectangle(0, 0, 1, bar_height, 0.4, 0.8, 1.0, 1.0);
bar_sprite = Sprite(bar_img);
bar_sprite.SetX(bar_x);
bar_sprite.SetY(bar_y);
bar_sprite.SetScale(0, 1);

fun boot_progress_callback(duration, progress) {
    bar_sprite.SetScale(bar_width * progress, 1);
}
Plymouth.SetBootProgressFunction(boot_progress_callback);

message_sprite = Sprite();
message_sprite.SetX(20);
message_sprite.SetY(Window.GetHeight() - 30);

fun display_message_callback(text) {
    message_sprite.SetImage(Image.Text(text, 0.6, 0.6, 0.65));
}
Plymouth.SetDisplayMessageFunction(display_message_callback);
PLYSCRIPT_TEXT
fi

# ── Activar el tema ───────────────────────────────────────────────────────────
plymouth-set-default-theme -R "$PLYMOUTH_THEME"

log "Tema Plymouth '${PLYMOUTH_THEME}' instalado y activado"

# ══════════════════════════════════════════════════════════════════════════════
#  SECCIÓN 12 — GRUB: FONDO PERSONALIZADO
# ══════════════════════════════════════════════════════════════════════════════
info "Configurando GRUB..."

# Reducir timeout de GRUB
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub

# Habilitar menú de GRUB (útil para dual-boot o troubleshooting)
sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=menu/' /etc/default/grub || \
  echo 'GRUB_TIMEOUT_STYLE=menu' >> /etc/default/grub

if [[ -n "$GRUB_BG_PATH" && -f "$GRUB_BG_PATH" ]]; then
  cp "$GRUB_BG_PATH" /boot/grub2/grub-custom-bg.png
  # Asegurarse que el módulo de fondo esté habilitado
  grep -q 'GRUB_BACKGROUND' /etc/default/grub && \
    sed -i "s|^GRUB_BACKGROUND=.*|GRUB_BACKGROUND=/boot/grub2/grub-custom-bg.png|" /etc/default/grub || \
    echo 'GRUB_BACKGROUND=/boot/grub2/grub-custom-bg.png' >> /etc/default/grub
  log "Fondo de GRUB configurado"
else
  warn "GRUB_BG_PATH no especificado o no existe. Saltando fondo de GRUB."
  warn "Para agregar fondo después: editar GRUB_BACKGROUND en /etc/default/grub"
fi

# Regenerar configuración de GRUB
if [[ -d /sys/firmware/efi ]]; then
  grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg
else
  grub2-mkconfig -o /boot/grub2/grub.cfg
fi

log "GRUB configurado"

# ══════════════════════════════════════════════════════════════════════════════
#  SECCIÓN 13 — OS-RELEASE PERSONALIZADO
# ══════════════════════════════════════════════════════════════════════════════
info "Personalizando identificación del sistema operativo..."

# Backup
cp /etc/os-release /etc/os-release.bak

# Agregar campos personalizados sin romper la compatibilidad
sed -i "s/^PRETTY_NAME=.*/PRETTY_NAME=\"${PRETTY_HOSTNAME} (Fedora Linux 44)\"/" /etc/os-release
# Agregar campo ANSI_COLOR para terminales que soportan neofetch/fastfetch
grep -q 'ANSI_COLOR' /etc/os-release || \
  echo 'ANSI_COLOR="1;36"' >> /etc/os-release  # cyan bold

log "os-release personalizado"

# ══════════════════════════════════════════════════════════════════════════════
#  SECCIÓN 14 — CONFIGURACIÓN INICIAL DE ZSH + HERRAMIENTAS
# ══════════════════════════════════════════════════════════════════════════════
info "Configurando zsh y herramientas de terminal para $REAL_USER..."

# Instalar Oh My Zsh para el usuario real
sudo -u "$REAL_USER" bash -c \
  'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended' || \
  warn "Oh My Zsh no se pudo instalar automáticamente. Instalalo manualmente."

# Instalar Starship prompt
curl -sS https://starship.rs/install.sh | sh -s -- --yes

# Agregar Starship al .zshrc del usuario
ZSHRC="${REAL_HOME}/.zshrc"
if [[ -f "$ZSHRC" ]]; then
  grep -q 'starship init' "$ZSHRC" || \
    echo 'eval "$(starship init zsh)"' >> "$ZSHRC"
fi

# Inicializar zoxide
grep -q 'zoxide init' "$ZSHRC" 2>/dev/null || \
  echo 'eval "$(zoxide init zsh)"' >> "$ZSHRC"

# Alias útiles
cat >> "$ZSHRC" <<'ALIASES'

# ── Aliases personalizados ────────────────────────────────────────────────────
alias ls='eza --icons --group-directories-first'
alias ll='eza -la --icons --group-directories-first'
alias lt='eza --tree --icons --level=2'
alias cat='bat --style=auto'
alias find='fd'
alias grep='rg'
alias cd='z'
alias top='btop'
alias du='dust'
alias ps='procs'
alias vim='nvim'
alias vi='nvim'
alias g='git'
alias lg='lazygit'
alias update='sudo dnf upgrade --refresh -y && flatpak update -y'
alias cleanup='sudo dnf autoremove -y && flatpak uninstall --unused -y'
ALIASES

chown "$REAL_USER:$REAL_USER" "$ZSHRC"
log "Zsh configurado"

# ══════════════════════════════════════════════════════════════════════════════
#  SECCIÓN 15 — DISPLAY MANAGER GRÁFICO (SDDM) + SESIÓN HYPRLAND
# ══════════════════════════════════════════════════════════════════════════════
info "Instalando y configurando SDDM como display manager gráfico..."

# ── Instalar SDDM ─────────────────────────────────────────────────────────────
dnf install -y sddm sddm-wayland

# ── Deshabilitar otros DM que pudieran estar activos ──────────────────────────
for dm in gdm lightdm lxdm; do
  systemctl disable "$dm" 2>/dev/null && warn "$dm deshabilitado" || true
done

# ── Habilitar SDDM como servicio de display manager ───────────────────────────
systemctl enable sddm
systemctl set-default graphical.target

# ── Configurar SDDM para Wayland / Hyprland ───────────────────────────────────
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/hyprland.conf <<'SDDMCONF'
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell

[Wayland]
CompositorCommand=Hyprland

[Theme]
Current=breeze

[Users]
# Ocultar usuarios del sistema (uid < 1000)
HideUsers=
MinimumUid=1000
SDDMCONF

# ── Registrar la sesión Hyprland en el sistema ────────────────────────────────
# SDDM muestra las sesiones en /usr/share/wayland-sessions/
# Hyprland ya instala hyprland.desktop, pero lo verificamos y creamos si falta
SESSIONS_DIR="/usr/share/wayland-sessions"
mkdir -p "$SESSIONS_DIR"

if [[ ! -f "${SESSIONS_DIR}/hyprland.desktop" ]]; then
  cat > "${SESSIONS_DIR}/hyprland.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Hyprland
Comment=An intelligent dynamic tiling Wayland compositor
Exec=Hyprland
Type=Application
DesktopNames=Hyprland
Keywords=wayland;compositor;tiling;
DESKTOP
  log "Sesión hyprland.desktop creada en $SESSIONS_DIR"
else
  log "Sesión hyprland.desktop ya existe"
fi

# ── Variables de entorno para la sesión Wayland ───────────────────────────────
# /etc/environment es leído por PAM/systemd al iniciar la sesión gráfica
cat >> /etc/environment <<'ENVVARS'

# ── Wayland / Hyprland ────────────────────────────────────────────────────────
XDG_SESSION_TYPE=wayland
XDG_CURRENT_DESKTOP=Hyprland
XDG_SESSION_DESKTOP=Hyprland
GDK_BACKEND=wayland,x11
QT_QPA_PLATFORM=wayland;xcb
QT_QPA_PLATFORMTHEME=qt6ct
QT_WAYLAND_DISABLE_WINDOWDECORATION=1
MOZ_ENABLE_WAYLAND=1
CLUTTER_BACKEND=wayland
SDL_VIDEODRIVER=wayland
NIXOS_OZONE_WL=1
ENVVARS

# ── Config mínima de Hyprland para el usuario ─────────────────────────────────
HYPR_CONFIG="${REAL_HOME}/.config/hypr"
mkdir -p "$HYPR_CONFIG"

if [[ ! -f "${HYPR_CONFIG}/hyprland.conf" ]]; then
cat > "${HYPR_CONFIG}/hyprland.conf" <<'HYPRCONF'
# ── Hyprland Config — Bootstrap ──────────────────────────────────────────────
# Documentación: https://wiki.hyprland.org/

# Monitores (ajustá a tu setup)
monitor=,preferred,auto,1

# Variables de entorno
env = XCURSOR_SIZE,24
env = QT_QPA_PLATFORMTHEME,qt6ct

# Input
input {
    kb_layout = latam
    follow_mouse = 1
    touchpad { natural_scroll = yes }
    sensitivity = 0
}

# General
general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(66ccffee) rgba(0099ffaa) 45deg
    col.inactive_border = rgba(24283baa)
    layout = dwindle
}

# Decoración
decoration {
    rounding = 10
    blur { enabled = true; size = 6; passes = 2 }
    drop_shadow = yes
    shadow_range = 8
    shadow_render_power = 2
}

# Animaciones
animations {
    enabled = yes
    bezier = myBezier, 0.05, 0.9, 0.1, 1.05
    animation = windows,    1, 5, myBezier
    animation = windowsOut, 1, 4, default, popin 80%
    animation = border,     1, 8, default
    animation = fade,       1, 5, default
    animation = workspaces, 1, 5, default
}

# Autostart
exec-once = waybar
exec-once = mako
exec-once = hyprpaper
exec-once = /usr/libexec/polkit-gnome-authentication-agent-1
exec-once = wl-paste --type text  --watch cliphist store
exec-once = wl-paste --type image --watch cliphist store

# Teclas (mod = Super/Windows)
$mod = SUPER

bind = $mod, Return,    exec, kitty
bind = $mod, Q,         killactive
bind = $mod, M,         exit
bind = $mod, E,         exec, nautilus
bind = $mod, Space,     exec, wofi --show drun
bind = $mod, F,         fullscreen
bind = $mod, V,         togglefloating

bind = $mod, 1, workspace, 1
bind = $mod, 2, workspace, 2
bind = $mod, 3, workspace, 3
bind = $mod, 4, workspace, 4
bind = $mod, 5, workspace, 5

bind = $mod SHIFT, 1, movetoworkspace, 1
bind = $mod SHIFT, 2, movetoworkspace, 2
bind = $mod SHIFT, 3, movetoworkspace, 3
bind = $mod SHIFT, 4, movetoworkspace, 4
bind = $mod SHIFT, 5, movetoworkspace, 5

bindm = $mod, mouse:272, movewindow
bindm = $mod, mouse:273, resizewindow

# Screenshot
bind = ,      Print, exec, grim -g "$(slurp)" - | swappy -f -
bind = $mod,  Print, exec, grim - | swappy -f -

HYPRCONF
fi

chown -R "$REAL_USER:$REAL_USER" "$HYPR_CONFIG"

log "SDDM instalado y habilitado → iniciará en modo gráfico al próximo boot"

# ══════════════════════════════════════════════════════════════════════════════
#  SECCIÓN 16 — LIMPIEZA FINAL
# ══════════════════════════════════════════════════════════════════════════════
info "Limpieza de paquetes huérfanos..."
dnf autoremove -y
flatpak uninstall --unused -y 2>/dev/null || true

# ══════════════════════════════════════════════════════════════════════════════
#  RESUMEN FINAL
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}${GREEN}"
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║   ✔  INSTALACIÓN COMPLETADA                         ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

echo -e "${CYAN}Sistema:${RESET}     ${PRETTY_HOSTNAME}"
echo -e "${CYAN}Hostname:${RESET}    ${STATIC_HOSTNAME}"
echo -e "${CYAN}Plymouth:${RESET}    ${PLYMOUTH_THEME}"
echo -e "${CYAN}Shell:${RESET}       zsh + Oh My Zsh + Starship"
echo -e "${CYAN}DE:${RESET}          Hyprland via SDDM (modo gráfico)"
echo ""
echo -e "${YELLOW}PRÓXIMOS PASOS:${RESET}"
echo "  1. Reiniciá: sudo reboot"
echo "  2. SDDM mostrará la pantalla de login gráfica → seleccioná 'Hyprland'"
echo "  3. Editá ~/.config/hypr/hyprland.conf para personalizar"
echo "  4. Para Plymouth con imagen: editá PLYMOUTH_IMG_PATH en este script"
echo "  5. Para GRUB con fondo:      editá GRUB_BG_PATH en este script"
echo "  6. Para Plymouth con imagen: editá PLYMOUTH_IMG_PATH en este script"
echo ""
warn "Si usás NVIDIA, agregá los módulos 'nvidia-drm.modeset=1' en GRUB_CMDLINE."
echo ""