#!/usr/bin/env python3
import atexit
import json
import logging
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

# ─── Colors ───────────────────────────────────────────────────────────────────

YLW = "\033[1;33m"
WHT = "\033[0;37m"
GRA = "\033[1;30m"
RED = "\033[0;31m"
GRN = "\033[0;32m"
MAG = "\033[1;35m"
PUR = "\033[0;35m"
CYN = "\033[0;36m"
BLU = "\033[1;34m"
ORA = "\033[0;33m"
NC  = "\033[0m"

# ─── Globals ──────────────────────────────────────────────────────────────────

AUR_HELPER = ""
AUR_CLR = ""
LAST_SELECTION = ""
SUDO_KEEPALIVE_EVENT = threading.Event()
TEMP_DIR = ""
LOG_FILE = ""

# ─── State File (idempotency tracker) ─────────────────────────────────────────

STATE_FILE = Path.home() / ".cache" / "guhwizard.state"

def load_state():
    """Load completed-phase set from disk."""
    if STATE_FILE.is_file():
        try:
            return set(json.loads(STATE_FILE.read_text()))
        except (json.JSONDecodeError, TypeError):
            return set()
    return set()

def save_state(state):
    """Persist completed-phase set to disk."""
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(sorted(state)))

def mark_done(phase):
    """Mark a phase as completed."""
    state = load_state()
    state.add(phase)
    save_state(state)

def is_done(phase):
    """Check whether a phase was already completed."""
    return phase in load_state()

# ─── Package query helpers ────────────────────────────────────────────────────

def is_pkg_installed(pkg):
    """Return True if *pkg* is already installed (pacman -Qq)."""
    return subprocess.run(
        ["pacman", "-Qq", pkg],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    ).returncode == 0

def is_service_enabled(unit):
    """Return True if a systemd unit is already enabled."""
    return subprocess.run(
        ["systemctl", "is-enabled", unit],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    ).returncode == 0

def is_user_service_enabled(unit):
    """Return True if a user-level systemd unit is already enabled."""
    return subprocess.run(
        ["systemctl", "--user", "is-enabled", unit],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    ).returncode == 0

# ─── Redirect stdin when piped ────────────────────────────────────────────────

def redirect_stdin():
    """If running via pipe (curl | python3), redirect stdin from /dev/tty."""
    if not os.isatty(sys.stdin.fileno()):
        try:
            sys.stdin = open("/dev/tty", "r")
        except OSError:
            print(f"{RED}[!] Cannot open /dev/tty for interactive input.{NC}")
            sys.exit(1)

# ─── Logging ──────────────────────────────────────────────────────────────────

class TeeHandler(logging.Handler):
    """Logging handler that writes to both a file and stdout (like tee)."""
    def __init__(self, filepath):
        super().__init__()
        self.filepath = filepath
        self.file = open(filepath, "a")

    def emit(self, record):
        msg = self.format(record)
        self.file.write(msg + "\n")
        self.file.flush()

    def close(self):
        self.file.close()
        super().close()

def setup_logging():
    global LOG_FILE
    cache_dir = Path.home() / ".cache"
    cache_dir.mkdir(parents=True, exist_ok=True)
    LOG_FILE = str(cache_dir / "guhwizard.log")

    tee = TeeHandler(LOG_FILE)
    tee.setFormatter(logging.Formatter("%(message)s"))
    logging.root.addHandler(tee)
    logging.root.setLevel(logging.INFO)

    log_file_handle = open(LOG_FILE, "a")

    class TeeStream:
        def __init__(self, original):
            self.original = original
            self.log = log_file_handle

        def write(self, data):
            self.original.write(data)
            self.log.write(data)
            self.log.flush()

        def flush(self):
            self.original.flush()
            self.log.flush()

        def fileno(self):
            return self.original.fileno()

        def isatty(self):
            return self.original.isatty()

    sys.stdout = TeeStream(sys.__stdout__)
    sys.stderr = TeeStream(sys.__stderr__)

    from datetime import datetime
    print(f"[{datetime.now()}]")

# ─── Prevent Root Execution ──────────────────────────────────────────────────

def check_root():
    if os.geteuid() == 0:
        print(f"{RED}[!] ERROR: Do not run this script as root.{NC}")
        print(f"{RED}==> AUR helpers cannot be built as root. "
              f"Please log in as a normal user with sudo privileges.{NC}")
        sys.exit(1)

# ─── Sudo Check ──────────────────────────────────────────────────────────────

def check_sudo():
    result = subprocess.run(["sudo", "-v"])
    if result.returncode != 0:
        print(f"{RED}[!] Please ensure you have sudo privileges "
              f"before running this script.{NC}")
        sys.exit(1)

# ─── Sudo keep-alive ─────────────────────────────────────────────────────────

def _sudo_keepalive_loop():
    while not SUDO_KEEPALIVE_EVENT.is_set():
        subprocess.run(["sudo", "-n", "true"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        SUDO_KEEPALIVE_EVENT.wait(60)

def start_sudo_keepalive():
    t = threading.Thread(target=_sudo_keepalive_loop, daemon=True)
    t.start()

# ─── Temp Directory ──────────────────────────────────────────────────────────

def setup_temp_dir():
    global TEMP_DIR
    TEMP_DIR = tempfile.mkdtemp(prefix="guhwizard.")

def cleanup():
    SUDO_KEEPALIVE_EVENT.set()
    if TEMP_DIR and os.path.isdir(TEMP_DIR):
        shutil.rmtree(TEMP_DIR, ignore_errors=True)

# ─── Run helper ──────────────────────────────────────────────────────────────

def run(cmd, check=True, **kwargs):
    return subprocess.run(cmd, check=check, **kwargs)

# ─── User Group Setup ────────────────────────────────────────────────────────

def user_in_group(user, group):
    """Return True if *user* is already a member of *group*."""
    result = subprocess.run(
        ["id", "-nG", user], capture_output=True, text=True
    )
    if result.returncode == 0:
        return group in result.stdout.split()
    return False

def setup_user_groups():
    groups = ["seat", "video", "audio", "render", "dbus"]
    user = os.environ.get("USER", os.getlogin())
    for g in groups:
        # Check group exists
        result = subprocess.run(["getent", "group", g],
                                stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL)
        if result.returncode == 0 and not user_in_group(user, g):
            subprocess.run(["sudo", "usermod", "-aG", g, user],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

# ─── AUR Helper Detection ────────────────────────────────────────────────────

def detect_aur():
    global AUR_HELPER, AUR_CLR

    helpers = {
        "yay": CYN, "paru": PUR,
        "pikaur": BLU,
    }

    for h, clr in helpers.items():
        if shutil.which(h):
            result = subprocess.run([h, "--version"],
                                    stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL)
            if result.returncode == 0:
                AUR_HELPER = h
                AUR_CLR = clr
                return True
    return False

# ─── Smart Installer (idempotent via --needed + pre-filter) ──────────────────

def smart_install(pkgs):
    """Install packages, skipping those already present."""
    repo_pkgs = []
    aur_pkgs = []

    for pkg in pkgs:
        if pkg == "oh-my-zsh":
            continue

        # ── Idempotency: skip if already installed ──
        if is_pkg_installed(pkg):
            continue

        result = subprocess.run(["pacman", "-Sp", pkg],
                                stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL)
        if result.returncode == 0:
            repo_pkgs.append(pkg)
        else:
            aur_pkgs.append(pkg)

    if not repo_pkgs and not aur_pkgs:
        print(f"{GRN}[OK] All packages already installed.{NC}")
        return

    if repo_pkgs:
        run(["sudo", "pacman", "-S", "--needed", "--noconfirm"] + repo_pkgs)

    if aur_pkgs:
        if AUR_HELPER:
            run([AUR_HELPER, "-S", "--needed", "--noconfirm"] + aur_pkgs)
        else:
            print(f"{RED}[!] AUR helper missing. Skipping: {' '.join(aur_pkgs)}{NC}")

# ─── Banner ──────────────────────────────────────────────────────────────────

BANNER_ART = r"""
                __            _                      __
   ____ ___  __/ /_ _      __(_)___  ____ __________/ /
  / __ `/ / / / __ \ | /| / / /_  / / __ `/ ___/ __  / 
 / /_/ / /_/ / / / / |/ |/ / / / /_/ /_/ / /  / /_/ /  
 \__, /\__,_/_/ /_/|__/|__/_/ /___/\__,_/_/   \__,_/   
/____/
"""

def print_banner():
    os.system("clear")
    print(f"{YLW}{BANNER_ART}{NC}")
    print(f"{YLW}Thank you for trying guhwm! :3{NC}")
    if AUR_HELPER:
        print(f"{YLW}AUR Helper: {AUR_CLR}{AUR_HELPER}{NC}")
    print()

# ─── Systemd Service Helper (idempotent) ─────────────────────────────────────

def enable_service(service):
    """Enable a systemd service. Skips if already enabled."""

    setup_user_groups()

    if service == "ly":
        print(f"{GRA}--> Deconflicting Display Managers...{NC}")
        subprocess.run(["sudo", "systemctl", "disable", "sddm", "gdm", "lightdm"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        dm_service = Path("/etc/systemd/system/display-manager.service")
        if dm_service.exists():
            subprocess.run(["sudo", "rm", "-f", str(dm_service)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["sudo", "systemctl", "mask", "getty@tty2.service"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    run(["sudo", "systemctl", "daemon-reload"])

    unit_to_enable = service
    result = subprocess.run(["systemctl", "list-unit-files", f"{service}.service"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if result.returncode != 0:
        result2 = subprocess.run(["systemctl", "list-unit-files", f"{service}@.service"],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result2.returncode == 0:
            unit_to_enable = f"{service}@tty2"
            print(f"{GRA}--> Template unit detected. Using {unit_to_enable}...{NC}")

    # ── Idempotency: skip if already enabled ──
    if is_service_enabled(unit_to_enable):
        print(f"{GRN}[OK] {unit_to_enable} is already enabled.{NC}")
        # Still start dbus if needed
        if service == "dbus":
            subprocess.run(["sudo", "systemctl", "start", "dbus"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return

    print(f"{GRA}--> Enabling service: {service}...{NC}")
    time.sleep(1)
    result = subprocess.run(["sudo", "systemctl", "enable", "--force", unit_to_enable])
    if result.returncode == 0:
        print(f"{GRN}[SUCCESS] {unit_to_enable} enabled.{NC}")
        if service == "dbus":
            subprocess.run(["sudo", "systemctl", "start", "dbus"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(1)
    else:
        print(f"{RED}[ERROR] Systemd could not enable {unit_to_enable}{NC}")
        input(f"{YLW}==> Press Enter to continue...{NC}")

    time.sleep(2)

# ─── Menu / Prompt Selection ─────────────────────────────────────────────────

def prompt_selection(title, mode, options):
    """
    Interactive menu with idempotent install.

    Returns:
        (selected, pkgs_installed)
    """
    global LAST_SELECTION

    print_banner()
    count = len(options)

    # ── Show installed status next to each option ──
    print(f"{YLW}==> {title}{NC}")
    for i, (clr, name, pkg, desc) in enumerate(options, 1):
        installed = is_pkg_installed(pkg) if pkg != "oh-my-zsh" else (Path.home() / ".oh-my-zsh").is_dir()
        tag = f" {GRN}[installed]{NC}" if installed else ""
        print(f"{i}) {clr}{name}{GRA} -- {WHT}{desc}{tag}{NC}")
    print("0) None/Skip")

    if mode == "multi":
        choice = input("Enter numbers (e.g., 1 2 3 or 1,2,3): ")
        choice = choice.replace(",", " ")
    else:
        choice = input("Select: ")

    choice = choice.strip()
    if choice == "0" or choice == "":
        LAST_SELECTION = ""
        return False, []

    pkgs_to_install = []
    for idx_str in choice.split():
        if not idx_str.isdigit():
            print(f"{ORA}[!] '{idx_str}' is not a valid number. Skipping...{NC}")
            continue

        idx = int(idx_str)
        if 1 <= idx <= count:
            pkg = options[idx - 1][2]
            pkgs_to_install.append(pkg)
            LAST_SELECTION = pkg
            if mode == "single":
                break
        else:
            print(f"{RED}[!] Choice {idx} is out of range. Skipping...{NC}")

    if not pkgs_to_install:
        LAST_SELECTION = ""
        return False, []

    if title != "AUR Helpers":
        for pkg in pkgs_to_install:
            if pkg == "ly" and not is_pkg_installed("ly"):
                result = subprocess.run(["pacman", "-Si", "ly"],
                                        stdout=subprocess.DEVNULL,
                                        stderr=subprocess.DEVNULL)
                if result.returncode != 0:
                    print(f"{GRA}--> Ly not in repos. Pre-installing Zig for AUR build...{NC}")
                    run(["sudo", "pacman", "-S", "--needed", "--noconfirm", "zig"])

        smart_install(pkgs_to_install)

    return True, pkgs_to_install

# ─── Network Check ───────────────────────────────────────────────────────────

def check_connection():
    result = subprocess.run(
        ["curl", "-Is", "--connect-timeout", "5", "https://www.google.com"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    if result.returncode != 0:
        print(f"{RED}[!] No internet connection.{NC}")
        return False

    result = subprocess.run(
        ["curl", "-Is", "--connect-timeout", "5", "https://aur.archlinux.org"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    if result.returncode != 0:
        print(f"{RED}[!] Internet is fine, but AUR is currently unreachable.{NC}")
        return False

    return True

# ─── System Preparation (idempotent) ─────────────────────────────────────────

def prepare_system():
    if is_done("prepare_system"):
        print(f"{GRN}[OK] System already prepared. Skipping...{NC}")
        return

    print_banner()
    print(f"{YLW}==> Preparing System...{NC}")

    print(f"{GRA}--> Verifying connectivity...{NC}")
    if not check_connection():
        sys.exit(1)
    print(f"{GRN}[OK] Network and AUR are available.{NC}")

    print(f"{GRA}--> Refreshing Arch Keyring...{NC}")
    run(["sudo", "pacman", "-Sy", "archlinux-keyring", "--noconfirm"])

    print(f"{GRA}--> Installing base-devel and git...{NC}")
    run(["sudo", "pacman", "-S", "--needed", "--noconfirm", "base-devel", "git"])

    mark_done("prepare_system")

# ─── AUR Helper Setup (idempotent) ───────────────────────────────────────────

def setup_aur_helper():
    global AUR_HELPER, AUR_CLR, LAST_SELECTION

    print(f"{GRA}--> Syncing package databases...{NC}")
    run(["sudo", "pacman", "-Syu", "--noconfirm"])

    # ── Idempotency: if a working AUR helper exists, skip entirely ──
    if AUR_HELPER:
        print(f"{GRN}[OK] AUR helper '{AUR_HELPER}' already available. Skipping setup.{NC}")
        return

    aur_options = [
        (CYN, "yay",    "yay",    "Yet Another Yogurt, fast and feature-rich, written in Go"),
        (PUR, "paru",   "paru",   "Feature-packed helper and pacman wrapper written in Rust"),
        (BLU, "pikaur", "pikaur", "AUR helper with minimal dependencies written in Python"),
    ]

    selected, pkgs = prompt_selection("AUR Helpers", "single", aur_options)

    if LAST_SELECTION:
        AUR_HELPER = LAST_SELECTION
        aur_helper_pkg = LAST_SELECTION
        color_map = {"yay": CYN, "paru": PUR, "pikaur": BLU}
        AUR_CLR = color_map.get(AUR_HELPER, NC)
        LAST_SELECTION = ""
    else:
        print(f"{RED}[ERROR] An AUR helper is required.{NC}")
        sys.exit(1)

    # ── Idempotency: if the chosen helper binary already works, skip build ──
    if shutil.which(AUR_HELPER):
        result = subprocess.run([AUR_HELPER, "--version"],
                                stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL)
        if result.returncode == 0:
            print(f"{GRN}[OK] {AUR_HELPER} is already installed and functional.{NC}")
            detect_aur()
            return

    # Conflict handling
    print(f"{GRA}--> Preparing environment for {AUR_HELPER}...{NC}")
    result = subprocess.run(
        f"pacman -Qq | grep -E '^{AUR_HELPER}'",
        shell=True, capture_output=True, text=True
    )
    conflicts = result.stdout.strip()

    if conflicts:
        print(f"{GRN}[+] Cleaning up existing {AUR_HELPER} files for a fresh start...{NC}")
        conflict_pkgs = conflicts.split()
        subprocess.run(
            ["sudo", "pacman", "-Rns", "--noconfirm"] + conflict_pkgs,
            stderr=subprocess.DEVNULL
        )

    # Pre-install compilers
    if AUR_HELPER == "yay":
        run(["sudo", "pacman", "-S", "--needed", "--noconfirm", "go"])
    elif AUR_HELPER == "paru":
        run(["sudo", "pacman", "-S", "--needed", "--noconfirm", "rust"])

    os.chdir(TEMP_DIR)
    run(["git", "clone", f"https://aur.archlinux.org/{aur_helper_pkg}.git"])
    os.chdir(aur_helper_pkg)

    env = os.environ.copy()
    nproc = subprocess.run(["nproc"], capture_output=True, text=True).stdout.strip()
    env["MAKEFLAGS"] = f"-j{nproc}"
    env["PKGEXT"] = ".pkg.tar"

    result = subprocess.run(["makepkg", "-si", "--noconfirm"], env=env)
    if result.returncode != 0:
        print(f"{RED}[!] Failed to build AUR helper. Please try manually.{NC}")
        sys.exit(1)

    os.chdir(Path.home())
    detect_aur()
    print()
    input(f"{YLW}==> {AUR_HELPER} is ready. Press Enter to continue...{NC}")

# ─── Install Base Packages (idempotent) ──────────────────────────────────────

def install_base():
    if is_done("install_base"):
        print(f"{GRN}[OK] Base packages already installed. Skipping...{NC}")
        return

    print_banner()
    print(f"{YLW}==> Installing Base System Packages...{NC}")

    base_pkgs = [
        # System Utilities
        "meson", "ninja", "tar", "curl", "jq", "bc", "7zip", "python-pipx",
        "xdg-desktop-portal", "xdg-utils", "xdg-user-dirs", "libxcb", "pcre2",
        
        # Network & Bluetooth Manager
        "networkmanager", "network-manager-applet",
        "bluez", "bluez-utils", "blueman",
        
        # Wayland & WM
        "glibc", "wayland", "wayland-protocols", "libinput", "libxkbcommon",
        "libdrm", "pixman", "libdisplay-info", "libliftoff", "seatd", "hwdata",
        "polkit-gnome",
        "wl-clipboard", "wlsunset", "xorg-xwayland", "mangowc-git",
        
        # UI Components
        "waybar", "rofi", "swaync", "libnotify", "adw-gtk-theme",
        
        # Audio Stack
        "alsa-utils", "pipewire", "pipewire-pulse", "wireplumber",
        
        # Fonts
        "noto-fonts", "noto-fonts-cjk", "noto-fonts-emoji",
        "ttf-jetbrains-mono-nerd", "cantarell-fonts",
    ]

    smart_install(base_pkgs)

    # Initialize standard user directories (idempotent)
    subprocess.run(["xdg-user-dirs-update"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    home = Path.home()
    for d in ["Public", "Templates"]:
        p = home / d
        if p.is_dir():
            shutil.rmtree(p, ignore_errors=True)

    setup_user_groups()

    print()
    input(f"{YLW}==> Base packages are installed. Press Enter to continue...{NC}")

    enable_service("seatd")
    print()

    # ── PipeWire user services (skip if already enabled) ──
    pw_units = ["pipewire", "pipewire-pulse", "wireplumber"]
    units_to_enable = [u for u in pw_units if not is_user_service_enabled(u)]
    if units_to_enable:
        print(f"{GRA}--> Enabling PipeWire user services...{NC}")
        subprocess.run(
            ["systemctl", "--user", "enable"] + units_to_enable,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
    else:
        print(f"{GRN}[OK] PipeWire user services already enabled.{NC}")

    # Enable NetworkManager (idempotent via enable_service guard)
    print(f"{GRA}--> Enabling NetworkManager...{NC}")
    if not is_service_enabled("NetworkManager"):
        run(["sudo", "systemctl", "enable", "--now", "NetworkManager"])
    else:
        print(f"{GRN}[OK] NetworkManager already enabled.{NC}")

    # Enable Bluetooth
    print(f"{GRA}--> Enabling Bluetooth service...{NC}")
    enable_service("bluetooth")
    time.sleep(2)

    mark_done("install_base")

# ─── Install Custom Repos (idempotent) ───────────────────────────────────────

def install_custom_repos():
    if is_done("install_custom_repos"):
        print(f"{GRN}[OK] Custom repos already set up. Skipping...{NC}")
        return

    print_banner()
    print(f"{YLW}==> Setting up guhwm...{NC}")

    guhwm_dir = os.path.join(TEMP_DIR, "guhwm")

    # 1. Clone guhwm (only configs/wallpapers matter — always clone to temp)
    result = subprocess.run(
        ["git", "clone", "--depth", "1",
         "https://github.com/Tapi-Mandy/guhwm.git", guhwm_dir]
    )
    if result.returncode != 0:
        print(f"{RED}[!] Failed to clone guhwm repository.{NC}")
        sys.exit(1)

    # 2. Copy configs (cp --backup=numbered won't overwrite destructively)
    confs_dir = os.path.join(guhwm_dir, "confs")
    if os.path.isdir(confs_dir):
        print(f"{GRA}--> Deploying configuration files...{NC}")
        config_dest = os.path.join(str(Path.home()), ".config")
        run(["cp", "-ra", "--backup=numbered",
             confs_dir + "/.", config_dest])

    # 3. Copy wallpapers
    wallpapers_dest = Path.home() / "Wallpapers"
    wallpapers_dest.mkdir(parents=True, exist_ok=True)
    wallpapers_src = os.path.join(guhwm_dir, "Wallpapers")
    run(["cp", "-ra", "--backup=numbered",
         wallpapers_src + "/.", str(wallpapers_dest)])

    # 4. Default wallpaper script
    default_wp = Path.home() / ".config" / "mango" / "scripts" / "default-wallpaper.sh"
    if default_wp.is_file():
        default_wp.chmod(0o755)
        print(f"{GRA}--> Setting default wallpaper...{NC}")
        result = subprocess.run(["bash", str(default_wp)], stderr=subprocess.DEVNULL)
        if result.returncode != 0:
            print(f"{GRA}--> Wallpaper is ready.{NC}")

    # 5. Nightlight script
    nightlight = Path.home() / ".config" / "mango" / "scripts" / "nightlight-toggle.sh"
    if nightlight.is_file():
        nightlight.chmod(0o755)
        print(f"{GRA}--> Nightlight is ready.{NC}")

    # 6. guhwall — skip if already installed
    print()
    if is_pkg_installed("guhwall"):
        print(f"{GRN}[OK] guhwall is already installed.{NC}")
    else:
        print(f"{YLW}==> Installing guhwall | Guh?? Set a Wallpaper!...{NC}")
        guhwall_dir = os.path.join(TEMP_DIR, "guhwall")
        result = subprocess.run(
            ["git", "clone", "--depth", "1",
             "https://github.com/Tapi-Mandy/guhwall.git", guhwall_dir]
        )
        if result.returncode == 0:
            subprocess.run(["makepkg", "-si", "--noconfirm"], cwd=guhwall_dir)
            print(f"{GRN}[SUCCESS] guhwall is installed.{NC}")
        else:
            print(f"{RED}[!] Failed to clone guhwall repository.{NC}")
            sys.exit(1)

    # 6b. Install pywal16 via pipx
    print()
    result = subprocess.run(
        ["pipx", "list"], capture_output=True, text=True
    )
    if result.returncode == 0 and "pywal16" in result.stdout:
        print(f"{GRN}[OK] pywal16 is already installed via pipx.{NC}")
    else:
        print(f"{YLW}==> Installing pywal16 via pipx...{NC}")
        subprocess.run(["pipx", "install", "pywal16"])
        # make sure pipx bin dir is on PATH for this session
        pipx_bin = Path.home() / ".local" / "bin"
        if str(pipx_bin) not in os.environ.get("PATH", ""):
            os.environ["PATH"] = f"{pipx_bin}:{os.environ.get('PATH', '')}"

    # 7. guhShot — skip if already installed
    print()
    if is_pkg_installed("guhshot"):
        print(f"{GRN}[OK] guhShot is already installed.{NC}")
    else:
        print(f"{YLW}==> Installing guhShot | Guh?? Take a Screenshot!...{NC}")
        guhshot_dir = os.path.join(TEMP_DIR, "guhShot")
        result = subprocess.run(
            ["git", "clone", "--depth", "1",
             "https://github.com/Tapi-Mandy/guhShot.git", guhshot_dir]
        )
        if result.returncode == 0:
            subprocess.run(["makepkg", "-si", "--noconfirm"], cwd=guhshot_dir)
            print(f"{GRN}[SUCCESS] guhShot is installed.{NC}")
        else:
            print(f"{RED}[!] Failed to clone guhShot repository.{NC}")
            sys.exit(1)

    print()
    input(f"{YLW}==> guhwm & guhwall & guhShot are installed. Press Enter to continue...{NC}")
    mark_done("install_custom_repos")

# ─── Optional Software (idempotent) ──────────────────────────────────────────

def sed_config(placeholder, replacement):
    """Replace a placeholder in mango config.conf.
    Idempotent: no-op if placeholder is already gone."""
    config = Path.home() / ".config" / "mango" / "config.conf"
    if config.is_file():
        try:
            text = config.read_text()
            if placeholder in text:
                text = text.replace(placeholder, replacement)
                config.write_text(text)
            else:
                print(f"{GRN}[OK] Config already updated (no '{placeholder}' placeholder found).{NC}")
        except Exception:
            pass

def optional_software():
    global LAST_SELECTION

    mango_dir = Path.home() / ".config" / "mango"
    mango_dir.mkdir(parents=True, exist_ok=True)

    print_banner()

    # ── SHELLS ──
    prompt_selection("Shells", "single", [
        (GRA, "Bash",      "bash",       "GNU Bourne Again Shell"),
        (RED, "Fish",      "fish",       "Friendly Interactive Shell"),
        (ORA, "Zsh",       "zsh",        "Z Shell"),
        (MAG, "Oh-My-Zsh", "oh-my-zsh",  "Community-driven framework for Zsh"),
    ])

    if LAST_SELECTION:
        target_shell = "bash"
        if LAST_SELECTION == "fish":
            target_shell = "fish"
        elif LAST_SELECTION in ("zsh", "oh-my-zsh"):
            target_shell = "zsh"

        if LAST_SELECTION == "oh-my-zsh":
            omz_dir = Path.home() / ".oh-my-zsh"
            if omz_dir.is_dir():
                # ── Idempotency: Oh-My-Zsh already present ──
                print(f"{GRN}[OK] Oh-My-Zsh is already installed.{NC}")
            else:
                print(f"{MAG}--> Running official Oh-My-Zsh installer...{NC}")
                run(["sudo", "pacman", "-S", "--needed", "--noconfirm", "zsh"])
                subprocess.run(
                    ["sh", "-c",
                     'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended']
                )
            zshrc = Path.home() / ".zshrc"
            if zshrc.is_file():
                text = zshrc.read_text()
                if 'ZSH_THEME="robbyrussell"' in text:
                    text = text.replace('ZSH_THEME="robbyrussell"', 'ZSH_THEME="agnoster"')
                    zshrc.write_text(text)

        shell_path = shutil.which(target_shell)
        if shell_path:
            user = os.environ.get("USER", os.getlogin())

            # Add to /etc/shells if not there (idempotent check)
            try:
                shells_text = Path("/etc/shells").read_text()
                if shell_path not in shells_text.splitlines():
                    print(f"{GRA}--> Adding {shell_path} to /etc/shells...{NC}")
                    subprocess.run(
                        f"echo '{shell_path}' | sudo tee -a /etc/shells > /dev/null",
                        shell=True
                    )
                else:
                    print(f"{GRN}[OK] {shell_path} already in /etc/shells.{NC}")
            except Exception:
                pass

            # Change shell only if different (already idempotent)
            result = subprocess.run(
                ["getent", "passwd", user],
                capture_output=True, text=True
            )
            if result.returncode == 0:
                current_shell = result.stdout.strip().split(":")[-1]
                if current_shell != shell_path:
                    print(f"{GRA}--> Changing default shell to {target_shell}...{NC}")
                    run(["sudo", "chsh", "-s", shell_path, user])
                else:
                    print(f"{GRN}[OK] Shell is already {target_shell}.{NC}")

        LAST_SELECTION = ""

    print()
    input(f"{YLW}==> Press Enter to continue...{NC}")

    # ── TERMINALS ──
    prompt_selection("Terminals", "single", [
        (ORA, "Alacritty", "alacritty", "Cross-platform, OpenGL terminal"),
        (YLW, "Foot",      "foot",      "Fast, lightweight Wayland terminal"),
        (BLU, "Ghostty",   "ghostty",   "Bleeding edge. Modern, fast, and feature-rich"),
        (MAG, "Kitty",     "kitty",     "For people who live inside the terminal"),
    ])

    if LAST_SELECTION:
        sed_config("YOURTERMINAL", LAST_SELECTION)
        LAST_SELECTION = ""

    # ── BROWSERS ──
    prompt_selection("Browsers", "multi", [
        (ORA, "Brave",       "brave-bin",       "Privacy-focused browser"),
        (ORA, "Firefox",     "firefox",         "Fast, Private & Safe"),
        (PUR, "Floorp",      "floorp-bin",      "Firefox fork focused on performance"),
        (CYN, "LibreWolf",   "librewolf-bin",   "Fork of Firefox focused on privacy"),
        (WHT, "Lynx",        "lynx",            "Text-based web browser"),
        (GRA, "Zen Browser", "zen-browser-bin", "Experience tranquillity while browsing"),
    ])

    # ── CHAT CLIENTS ──
    prompt_selection("Chat Clients", "multi", [
        (BLU, "Discord",  "discord",         "All-in-one voice and text chat"),
        (BLU, "Dissent",  "dissent-bin",     "Discord client written in Go/GTK4"),
        (CYN, "Telegram", "telegram-desktop", "Official Telegram Desktop client"),
        (MAG, "Vesktop",  "vesktop-bin",     "The cutest Discord client"),
        (CYN, "WebCord",  "webcord-bin",     "Discord client using the web version"),
    ])

    # ── FILE MANAGERS ──
    gui_file_managers = {"nautilus", "nemo", "dolphin"}
    prompt_selection("File Managers", "single", [
        (BLU, "Nautilus", "nautilus", "GNOME's file manager"),
        (WHT, "Nemo",    "nemo",     "Cinnamon's file manager"),
        (GRA, "nnn",     "nnn",      "The unorthodox terminal file manager"),
        (ORA, "ranger",  "ranger",   "Vim-inspired terminal file manager"),
        (YLW, "Yazi",    "yazi",     "Blazing fast terminal file manager written in Rust"),
    ])

    if LAST_SELECTION:
        if LAST_SELECTION in gui_file_managers:
            # GUI file managers don't need a terminal wrapper
            sed_config("YOURTERMINAL -e YOURFILEMANAGER", LAST_SELECTION)
        else:
            # TUI file managers need to run inside a terminal
            sed_config("YOURFILEMANAGER", LAST_SELECTION)
        LAST_SELECTION = ""

    # ── EDITORS ──
    prompt_selection("Editors", "multi", [
        (PUR, "Emacs",        "emacs",          "The extensible, self-documenting editor"),
        (YLW, "Geany",        "geany",          "Flyweight IDE"),
        (GRN, "Neovim",       "neovim",         "Vim-fork focused on extensibility"),
        (GRA, "Sublime Text", "sublime-text-4", "Sophisticated text editor"),
        (GRN, "Vim",          "vim",            "The ubiquitous text editor"),
        (BLU, "VSCodium",     "vscodium-bin",   "Free/Libre Open Source VSCode"),
    ])

    if LAST_SELECTION:
        sed_config("YOUREDITOR", LAST_SELECTION)
        LAST_SELECTION = ""

    # ── GRAPHICS ──
    prompt_selection("Graphics", "multi", [
        (ORA, "Blender", "blender", "3D creation suite for modeling, rigging, and animation"),
        (GRA, "GIMP",    "gimp",    "GNU Image Manipulation Program"),
        (MAG, "Krita",   "krita",   "Digital painting studio"),
    ])

    # ── MEDIA ──
    prompt_selection("Media", "multi", [
        (WHT, "imv",        "imv",        "Command-line image viewer for Wayland and X11"),
        (BLU, "Loupe",      "loupe",      "Simple and modern image viewer from GNOME"),
        (PUR, "mpv",        "mpv",        "Free, open source, and cross-platform media player"),
        (RED, "OBS Studio", "obs-studio", "Free, open-source live streaming and recording"),
        (CYN, "swayimg",    "swayimg",    "Lightweight image viewer for Wayland"),
        (ORA, "VLC",        "vlc",        "Multi-platform multimedia player and framework"),
    ])

    # ── PDF READERS ──
    prompt_selection("PDF Readers", "multi", [
        (GRN, "Evince",  "evince",  "GNOME document viewer"),
        (PUR, "MuPDF",   "mupdf",   "Lightweight PDF and XPS viewer"),
        (GRA, "Zathura", "zathura", "Minimalist document viewer"),
    ])

    # ── OFFICE SUITES ──
    prompt_selection("Office Suites", "multi", [
        (BLU, "LibreOffice Fresh", "libreoffice-fresh", "Latest LibreOffice release"),
        (GRN, "LibreOffice Still", "libreoffice-still", "Stable LibreOffice release"),
        (ORA, "OpenOffice",        "openoffice-bin ",   "Free and Open Productivity Suite"),
    ])

    # ── UTILITIES ──
    prompt_selection("Utilities", "multi", [
        (GRA, "Fastfetch", "fastfetch", "Like neofetch, but much faster"),
        (MAG, "fzf",       "fzf",       "Command-line fuzzy finder"),
        (GRA, "htop",      "htop",      "Interactive process viewer"),
        (GRA, "nvtop",     "nvtop",     "GPUs process monitor for AMD, NVIDIA, and Intel"),
        (CYN, "tldr",      "tldr",      "Simplified and community-driven man pages"),
        (MAG, "uwufetch",  "uwufetch",  "Cutest system info fetcher"),
    ])

    # ── EMULATORS ──
    prompt_selection("Emulators", "multi", [
        (BLU, "Dolphin",     "dolphin-emu-git",   "Gamecube & Wii emulator"),
        (YLW, "DuckStation", "duckstation-git",   "PS1 Emulator aiming for accuracy and support"),
        (GRN, "melonDS",     "melonds-bin",       "DS emulator, sorta"),
        (BLU, "PCSX2",       "pcsx2",             "PlayStation 2 emulator"),
        (GRA, "RetroArch",   "retroarch",         "Frontend for emulators, game engines and media players."),
        (GRN, "ScummVM",     "scummvm",           "'Virtual machine' for several classic graphical point-and-click adventure games."),
        (GRN, "xemu",        "xemu-bin",          "Emulator for the original Xbox"),
    ])

    # ── DISPLAY MANAGER ──
    selected, pkgs = prompt_selection("Display Manager", "single", [
        (PUR, "Ly", "ly", "TUI display manager"),
    ])

    if selected and LAST_SELECTION:
        print(f"{GRA}--> Verifying installation...{NC}")
        if is_pkg_installed("ly"):
            enable_service("ly")
            print()
            input(f"{YLW}==> Ly setup finished. Press Enter to continue...{NC}")
        else:
            print(f"{RED}[ERROR] Ly package not found in database.{NC}")
            input(f"{YLW}==> Press Enter to continue...{NC}")
        LAST_SELECTION = ""

# ─── Outro ────────────────────────────────────────────────────────────────────

OUTRO_ART = r"""
     *                  *
         __                *
      ,db'    *     *
     ,d8/       *        *    *
     888
     `db\       *     *
       `o`_                    **
  *               *   *    _      *
        *                 / )
     *    (\__/) *       ( (  *
   ,-.,-.,)    (.,-.,-.,-.) ).,-.,-. 
  | @|  ={      }= | @|  / / | @|o |
 _j__j__j_)     `-------/ /__j__j__j_
 ________(               /___________
  |  | @| \              || o|O | @|
  |o |  |,'\       ,   ,'"|  |  |  |
 vV\|/vV|`-'\  ,---\   | \Vv\hjwVv\//v
            _) )    `. \ /
           (__/       ) )
                     (_/
"""

def print_outro():
    print_banner()
    print(OUTRO_ART)
    print(f"{GRN}System setup complete! Everything is ready.{NC}")
    print()
    rb = input("Would you like to reboot now? (y/n): ").strip()

    if rb.lower() == "y":
        subprocess.run(["systemctl", "reboot"])

# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    redirect_stdin()
    check_root()
    check_sudo()
    start_sudo_keepalive()
    setup_logging()
    setup_temp_dir()
    atexit.register(cleanup)

    prepare_system()       # Refresh keys, install git/base-devel
    detect_aur()           # Check if a helper is already there
    setup_aur_helper()     # Repair or Install AUR helper
    install_base()         # System utils, Wayland, Audio, Fonts
    install_custom_repos() # Clone configs, Wallpapers, guhwall, guhShot
    optional_software()    # Shells, Browsers, Apps, and 'sed' tweaks
    print_outro()          # Final ASCII and reboot prompt

if __name__ == "__main__":
    main()
