#!/bin/bash

# ===============================================================
# --- guhwizard -------------------------------------------------
# ===============================================================

# Colors (Midnight Rose Theme)
MAGENTA='\033[1;35m'
ROSE='\033[0;31m' 
NC='\033[0m' # No Color

echo -e "${MAGENTA}[*] Initializing guhwizard...${NC}"

# 1. Check for Sudo
if [ "$EUID" -eq 0 ]; then
  echo -e "${ROSE}[!] Please run this script as a standard user (not root).${NC}"
  exit 1
fi

# Sudo Keep-Alive
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# 2. Dependencies
echo -e "${MAGENTA}[*] Installing system dependencies...${NC}"
sudo pacman -Sy --noconfirm python python-pip git base-devel npm nodejs > /dev/null 2>&1

# 3. TUI Libraries
echo -e "${MAGENTA}[*] Setting up Python TUI libraries...${NC}"
pip install rich questionary --break-system-packages --no-warn-script-location > /dev/null 2>&1

# 4. Python Installer Generation
echo -e "${MAGENTA}[*] Launching guhwizard...${NC}"

cat << 'EOF' > installer.py
import os
import sys
import subprocess
import shutil
import time
from rich.console import Console
from rich.panel import Panel
from rich.text import Text
from rich.table import Table
from rich.align import Align
from rich.progress import Progress, SpinnerColumn, TextColumn
from rich import box
import questionary

# --- Configuration ---
REPO_URL = "https://github.com/Tapi-Mandy/guhwm"
CONFIG_DIR = os.path.expanduser("~/.config/guhwm")

console = Console()

# --- Colors & Styles (Midnight Rose Theme) ---
C_PRIMARY = "bold magenta"     
C_ACCENT = "#ff5faf"           
C_DARK = "#5f005f"             
C_DIM = "dim #d75f87"          
C_SUCCESS = "bold green"
C_ERROR = "bold red"

# --- Package Definitions ---
class Pkg:
    def __init__(self, name, desc, pkg_name=None, is_aur=False, binary_name=None):
        self.name = name
        self.desc = desc
        self.pkg_name = pkg_name if pkg_name else name.lower()
        self.is_aur = is_aur
        self.binary_name = binary_name if binary_name else self.pkg_name

# --- Utilities ---
def run_cmd(cmd, shell=False, show_output=False):
    try:
        if show_output:
            subprocess.check_call(cmd, shell=shell)
        else:
            subprocess.check_call(cmd, shell=shell, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except subprocess.CalledProcessError:
        return False

def clear():
    os.system('cls' if os.name == 'nt' else 'clear')

def print_header():
    clear()
    ascii_art = r"""
              _               _                  _ 
   __ _ _   _| |__  __      _(_)______ _ _ __ __| |
  / _` | | | | '_ \ \ \ /\ / / |_  / _` | '__/ _` |
 | (_| | |_| | | | | \ V  V /| |/ / (_| | | | (_| |
  \__, |\__,_|_| |_|  \_/\_/ |_/___\__,_|_|  \__,_|
  |___/                                            
    """
    logo = Text(ascii_art, style=C_PRIMARY)
    subtitle = Text("Guh Window Manager Installer", style=C_DIM)
    content = Align.center(Text.assemble(logo, "\n", subtitle))
    console.print(Panel(content, border_style=C_DARK, box=box.ROUNDED, padding=(1, 2), expand=True))

def print_section(title):
    console.print()
    console.rule(f"[{C_PRIMARY}]{title}[/]", style=C_DARK)
    console.print()

# --- Core Logic ---

def install_pacman_packages(packages, description="Installing packages..."):
    if not packages: return
    
    with Progress(
        SpinnerColumn(style=C_ACCENT),
        TextColumn("[bold white]{task.description}"),
        transient=True
    ) as progress:
        progress.add_task(description, total=None)
        cmd = ["sudo", "pacman", "-S", "--noconfirm", "--needed"] + packages
        run_cmd(cmd, show_output=False)

def install_aur_package(package_name, helper):
    if not helper: return False
    cmd = [helper, "-S", "--noconfirm", "--needed", package_name]
    return run_cmd(cmd, show_output=True)

def setup_aur_helper(choice):
    if choice == "None": return None
    if shutil.which(choice.lower()): return choice.lower()
    
    console.print(f"   [yellow]➤[/yellow] Installing {choice}...", style="dim")
    
    build_dir = os.path.expanduser(f"~/{choice.lower()}_build_temp")
    repo = f"https://aur.archlinux.org/{choice.lower()}-bin.git"
    
    if os.path.exists(build_dir): shutil.rmtree(build_dir)

    try:
        run_cmd(["git", "clone", repo, build_dir], show_output=True)
        os.chdir(build_dir)
        os.system("makepkg -si --noconfirm")
        os.chdir(os.path.expanduser("~"))
        shutil.rmtree(build_dir)
        return choice.lower()
    except Exception as e:
        console.print(f"   [{C_ERROR}]✖[/] Failed to install {choice}", style="dim")
        return None

# --- Tool Compilation Logic ---

def install_tool_from_source(name, repo, build_cmds, is_sudo_install=True):
    """Generic function to clone, build, and install a tool."""
    console.print(f"   [cyan]➤[/cyan] Installing [bold]{name}[/bold]...", style="dim")
    build_dir = os.path.expanduser(f"~/guh_build_{name.lower()}")
    
    if os.path.exists(build_dir):
        shutil.rmtree(build_dir)
        
    try:
        # Clone
        run_cmd(["git", "clone", repo, build_dir], show_output=False)
        os.chdir(build_dir)
        
        # Run build commands
        for cmd in build_cmds:
            # Show output for build steps as they can take time/fail
            console.print(f"      [dim]Running: {cmd}[/dim]")
            exit_code = os.system(f"{cmd} > /dev/null 2>&1")
            if exit_code != 0:
                raise Exception(f"Command failed: {cmd}")
                
        os.chdir(os.path.expanduser("~"))
        shutil.rmtree(build_dir)
        console.print(f"   [{C_SUCCESS}]✔ {name} installed.[/]")
        return True
    except Exception as e:
        console.print(f"   [{C_ERROR}]✖ Failed to install {name}: {e}[/]")
        return False

def install_config_file(src_path, dest_dir, file_name):
    if not os.path.exists(src_path): return
    full_dest_dir = os.path.expanduser(dest_dir)
    full_dest_path = os.path.join(full_dest_dir, file_name)
    os.makedirs(full_dest_dir, exist_ok=True)
    
    status_icon = ""
    status_text = ""
    
    if os.path.exists(full_dest_path):
        if questionary.confirm(f"Config file '{file_name}' already exists in {dest_dir}. Overwrite?").ask():
            shutil.copy(src_path, full_dest_path)
            status_icon = "[yellow]![/yellow]"
            status_text = f"[dim]Overwrote {file_name}[/dim]"
        else:
            status_icon = "[dim]-[/dim]"
            status_text = f"[dim]Skipped {file_name}[/dim]"
    else:
        shutil.copy(src_path, full_dest_path)
        status_icon = "[green]✔[/green]"
        status_text = f"[dim]Installed {file_name}[/dim]"
        
    console.print(f" {status_icon} {status_text}")

def install_polybar_config(config_dir):
    """Install all polybar configuration files."""
    polybar_src = os.path.join(config_dir, "polybar")
    polybar_dest = os.path.expanduser("~/.config/polybar")
    
    if not os.path.exists(polybar_src):
        console.print(f"   [{C_ERROR}]✖ Polybar config not found in repo[/]")
        return False
    
    os.makedirs(polybar_dest, exist_ok=True)
    
    # List of polybar files to install
    polybar_files = ["config.ini", "launch.sh", "toggle.sh", "salah.sh"]
    
    for filename in polybar_files:
        src = os.path.join(polybar_src, filename)
        dest = os.path.join(polybar_dest, filename)
        
        if os.path.exists(src):
            if os.path.exists(dest):
                # For scripts, always overwrite; for config, ask
                if filename == "config.ini":
                    if questionary.confirm(f"Polybar config.ini exists. Overwrite?").ask():
                        shutil.copy(src, dest)
                        console.print(f"   [yellow]![/yellow] [dim]Overwrote {filename}[/dim]")
                    else:
                        console.print(f"   [dim]-[/dim] [dim]Skipped {filename}[/dim]")
                        continue
                else:
                    shutil.copy(src, dest)
                    console.print(f"   [yellow]![/yellow] [dim]Overwrote {filename}[/dim]")
            else:
                shutil.copy(src, dest)
                console.print(f"   [green]✔[/green] [dim]Installed {filename}[/dim]")
            
            # Make scripts executable
            if filename.endswith(".sh"):
                os.chmod(dest, 0o755)
    
    return True

# --- Categories ---

base_pkgs = [
    # Essential X11 components
    "xorg", "xorg-xinit",

    # Compilation Libraries
    "libx11", "libxinerama", "libxft", "imlib2", "freetype2",

    # Core
    "kitty", "picom", "rofi", "feh", "zip", "unzip", "jq", "curl", "npm", "nodejs", "sxhkd",

    # Polybar (status bar)
    "polybar",

    # Audio
    "alsa-utils", "pulseaudio", "pulseaudio-alsa",

    # Fonts
    "noto-fonts", "noto-fonts-cjk", "noto-fonts-emoji", "ttf-jetbrains-mono-nerd"
]

browsers = [
    Pkg("Brave", "Privacy-focused browser blocking trackers", "brave-bin", is_aur=True),
    Pkg("Firefox", "Fast, Private & Safe Web Browser", "firefox"),
    Pkg("Librewolf", "Fork of Firefox focused on privacy", "librewolf-bin", is_aur=True),
    Pkg("Lynx", "Text-based web browser", "lynx"),
]

comm_apps = [
    Pkg("AyuGram", "Telegram client with good customization", "ayugram-desktop-bin", is_aur=True),
    Pkg("Discord", "All-in-one voice and text chat", "discord"),
    Pkg("Telegram", "Official Telegram Desktop client", "telegram-desktop"),
    Pkg("Vesktop", "The cutest Discord client", "vesktop-bin", is_aur=True),
    Pkg("Webcord", "Discord client that uses the web version", "webcord-bin", is_aur=True),
]

dev_tools = [
    Pkg("Emacs", "Extensible, customizable text editor", "emacs"),
    Pkg("Geany", "Flyweight IDE", "geany"),
    Pkg("Nano", "Simple terminal text editor", "nano"),
    Pkg("Neovim", "Fork of Vim aiming to improve user experience", "neovim"),
    Pkg("Sublime", "Sophisticated text editor for code", "sublime-text-4", is_aur=True),
    Pkg("Vim", "Vi iMproved, highly configurable text editor", "vim"),
    Pkg("VSCodium", "Free/Libre Open Source binary of VSCode", "vscodium-bin", is_aur=True),
]

misc_apps = [
    Pkg("Htop", "Interactive process viewer", "htop"),
    Pkg("Krita", "A full-featured free digital painting studio", "krita"),
    Pkg("Mpv", "Command line video player", "mpv"),
    Pkg("Redshift", "Adjusts screen color temperature", "redshift"),
    Pkg("Uwufetch", "Cute system information fetcher", "uwufetch"),
    Pkg("Yazi", "Blazing fast terminal file manager", "yazi"),
]

shells = [
    Pkg("Bash", "The GNU Bourne Again shell", "bash"),
    Pkg("Ksh", "KornShell, a classic Unix shell", "ksh"),
    Pkg("Oh My Zsh", "Community-driven framework for Zsh", "zsh"), 
    Pkg("Zsh", "Shell designed for advanced use", "zsh"),
]

# --- Main Execution ---

def main():
    print_header()

    # 1. Install Base
    print_section("Base System")
    
    install_pacman_packages(base_pkgs, "Installing base packages...")
    
    run_cmd(["fc-cache", "-fv"], show_output=False)
    
    console.print(Align.center(f"\n[{C_SUCCESS}]✔ Base packages installed.[/]"))
    time.sleep(1.5)

    # 2. Welcome
    print_header()
    welcome_msg = "Welcome to the [bold magenta]guhwm[/bold magenta] installer.\n\nThis wizard will set up your environment,\ninstall applications, and configure the window manager.\n"
    console.print(Panel(Align.center(welcome_msg), border_style=C_DARK, box=box.ROUNDED, title="Welcome", padding=(1, 4)))
    
    if not questionary.confirm("Ready to proceed?").ask():
        sys.exit()

    # 3. AUR Helper
    print_header()
    print_section("AUR Helper")
    console.print(Align.center("[dim]Required for many applications (Brave, Vesktop, etc.)[/dim]\n"))
    
    aur_choice = questionary.select("Choose an AUR helper:", choices=["Yay", "Paru", "None"]).ask()
    aur_helper = setup_aur_helper(aur_choice)

    # 4. Categories Logic
    categories = [
        ("Browsers", browsers),
        ("Communication", comm_apps),
        ("Developer Tools", dev_tools),
        ("Miscellaneous Tools", misc_apps),
    ]

    for cat_name, pkg_list in categories:
        print_header()
        print_section(cat_name)
        
        available_pkgs = [p for p in pkg_list if not (p.is_aur and not aur_helper)]
        disabled_pkgs = [p for p in pkg_list if p.is_aur and not aur_helper]

        table = Table(box=box.ROUNDED, border_style=C_DARK, header_style=C_PRIMARY, show_lines=False)
        table.add_column("Software", style=C_ACCENT)
        table.add_column("Source", style="cyan", justify="center")
        table.add_column("Description", style="white")

        for p in available_pkgs:
            source = "AUR" if p.is_aur else "Pacman"
            table.add_row(p.name, source, p.desc)
        
        if disabled_pkgs:
             table.add_row("[dim]Others[/dim]", "[dim]AUR[/dim]", f"[dim]({len(disabled_pkgs)} hidden - needs AUR helper)[/dim]")

        console.print(Align.center(table))
        console.print()
        
        choices = [p.name for p in available_pkgs] + ["None"]
        selected_names = questionary.checkbox(
            f"Select {cat_name} to install:",
            choices=choices,
            instruction="(Press <space> to select, <enter> to proceed)"
        ).ask()

        if selected_names and "None" not in selected_names:
            console.print()
            pacman_queue = []
            
            for name in selected_names:
                pkg = next((p for p in available_pkgs if p.name == name), None)
                if pkg:
                    if pkg.is_aur and aur_helper:
                        console.print(f"   [cyan]➤[/cyan] Installing [bold]{pkg.name}[/bold] (AUR)...")
                        install_aur_package(pkg.pkg_name, aur_helper)
                    else:
                        pacman_queue.append(pkg.pkg_name)
            
            if pacman_queue:
                install_pacman_packages(pacman_queue, f"Installing {len(pacman_queue)} packages...")
            
            time.sleep(0.5)

    # 5. Shell Selection
    print_header()
    print_section("Shell Selection")
    
    s_table = Table(box=box.ROUNDED, border_style=C_DARK, header_style=C_PRIMARY)
    s_table.add_column("Shell", style=C_ACCENT)
    s_table.add_column("Description")
    for s in shells: s_table.add_row(s.name, s.desc)
    console.print(Align.center(s_table))
    console.print()

    shell_choice = questionary.select("Which shell should be the default?", choices=[s.name for s in shells]).ask()
    if shell_choice:
        sel_shell = next(s for s in shells if s.name == shell_choice)
        install_pacman_packages([sel_shell.pkg_name], f"Installing {sel_shell.name}...")
        
        if shell_choice == "Oh My Zsh":
            console.print(Align.center("Installing Oh My Zsh..."))
            install_pacman_packages(["zsh", "curl", "git"], "Installing deps...")
            os.system('sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended')
            try: subprocess.run(["chsh", "-s", "/bin/zsh", os.environ.get("USER", "")])
            except: console.print(Align.center("[red]Could not auto-change shell. Do it manually.[/red]"))
        else:
            bin_path = f"/bin/{sel_shell.pkg_name}"
            try: subprocess.run(["chsh", "-s", bin_path, os.environ.get("USER", "")])
            except: pass

    # 6. Base Environment Tools Installation
    print_header()
    print_section("Installing Base Environment Tools")
    
    # xsnap
    install_tool_from_source("xsnap", "https://github.com/w8z4rd/xsnap", ["sudo make install"])
    
    # pino
    install_tool_from_source("pino", "https://github.com/Pixel2175/pino", ["python install.py"])
    
    # guhwall (Installed via curl script)
    console.print(f"   [cyan]➤[/cyan] Installing [bold]guhwall[/bold]...", style="dim")
    # Silence output but verify success by checking if binary exists
    os.system("curl -sS https://raw.githubusercontent.com/Tapi-Mandy/guhwall/main/install.sh | bash > /dev/null 2>&1")
    
    # Check if binary exists instead of relying on exit code to avoid false red text
    if shutil.which("guhwall"):
        console.print(f"   [{C_SUCCESS}]✔ guhwall installed.[/]")
    else:
        console.print(f"   [{C_ERROR}]✖ Failed to install guhwall[/]")

    # 7. Install guhwm
    print_header()
    print_section(f"Installing guhwm")
    
    # Clone to ~/.config/guhwm
    if os.path.exists(CONFIG_DIR):
        console.print(Align.center(f"[yellow]Cleaning up previous installation at {CONFIG_DIR}...[/yellow]"))
        os.system(f"sudo rm -rf {CONFIG_DIR}")
    
    # Ensure parent dir exists
    os.makedirs(os.path.dirname(CONFIG_DIR), exist_ok=True)
    
    run_cmd(["git", "clone", REPO_URL, CONFIG_DIR], show_output=True)
    
    if os.path.exists(CONFIG_DIR):
        console.print()
        
        # Configs (Moved to their own folders per request)
        install_config_file(f"{CONFIG_DIR}/picom.conf", "~/.config/picom", "picom.conf")
        install_config_file(f"{CONFIG_DIR}/config.rasi", "~/.config/rofi", "config.rasi")
        
        # Polybar configuration files
        console.print(Align.center("\n[dim]Installing Polybar configuration...[/dim]"))
        install_polybar_config(CONFIG_DIR)
        
        # Wallpapers (Copy to system and keep in config)
        os.system("sudo mkdir -p /usr/share/backgrounds/Wallpapers")
        if os.path.exists(f"{CONFIG_DIR}/Wallpapers"):
            os.system(f"sudo cp -r {CONFIG_DIR}/Wallpapers/* /usr/share/backgrounds/Wallpapers/")
            console.print(f" [green]✔[/green] [dim]Installed Wallpapers[/dim]")

        # Mod Key
        print_header()
        print_section("Configuration")
        mod_choice = questionary.select("Which key to set as the 'Mod' key?", choices=["Alt (Default / Mod1)", "Windows/Super (Mod4)"]).ask()
        
        # Determine sxhkd modifier
        sxhkd_mod = "super" # default assumption for windows key
        
        if "Windows" in mod_choice:
            console.print(Align.center("[yellow]Applying the Windows/Super key...[/yellow]"))
            sxhkd_mod = "super"
            c_path = f"{CONFIG_DIR}/dwm/config.def.h"
            if os.path.exists(c_path):
                with open(c_path, 'r') as f: c = f.read()
                c = c.replace("#define MODKEY Mod1Mask", "#define MODKEY Mod4Mask")
                with open(c_path, 'w') as f: f.write(c)
        else:
            sxhkd_mod = "alt"

        # Generate sxhkdrc
        console.print(Align.center("[dim]Generating sxhkdrc...[/dim]"))
        sxhkd_dir = os.path.expanduser("~/.config/sxhkd")
        if not os.path.exists(sxhkd_dir): os.makedirs(sxhkd_dir)
        with open(os.path.join(sxhkd_dir, "sxhkdrc"), "w") as f:
            f.write(f"""# Mod + Shift + s: Screenshot to Clipboard
{sxhkd_mod} + shift + s
    ~/.local/bin/xsnap copy

# Mod + Shift + a: Screenshot to Google Lens
{sxhkd_mod} + shift + a
    ~/.local/bin/xsnap lens
""")
        console.print(f" [green]✔[/green] [dim]Configured sxhkd[/dim]")

        # Salah Times (Prayer Times) - Now configured via Polybar
        if questionary.confirm("Enable Salah Times (Prayer Times) in the bar?").ask():
            console.print(Align.center("[yellow]Enabling Salah...[/yellow]"))
            
            # Update polybar launch.sh to enable salah
            polybar_launch = os.path.expanduser("~/.config/polybar/launch.sh")
            if os.path.exists(polybar_launch):
                try:
                    with open(polybar_launch, 'r') as f: launch_content = f.read()
                    # Enable salah (it's enabled by default, but ensure it is)
                    launch_content = launch_content.replace('SALAH_ENABLED="false"', 'SALAH_ENABLED="true"')
                    with open(polybar_launch, 'w') as f: f.write(launch_content)
                    console.print(f" [green]✔[/green] [dim]Enabled Salah in Polybar[/dim]")
                except Exception as e:
                    console.print(Align.center(f"[red]Failed to enable Salah: {e}[/red]"))
            else:
                console.print(Align.center("[yellow]Polybar launch.sh not found, skipping Salah config.[/yellow]"))
        else:
            # Disable salah
            polybar_launch = os.path.expanduser("~/.config/polybar/launch.sh")
            if os.path.exists(polybar_launch):
                try:
                    with open(polybar_launch, 'r') as f: launch_content = f.read()
                    launch_content = launch_content.replace('SALAH_ENABLED="true"', 'SALAH_ENABLED="false"')
                    with open(polybar_launch, 'w') as f: f.write(launch_content)
                    console.print(f" [dim]-[/dim] [dim]Salah disabled[/dim]")
                except Exception as e:
                    pass

        # Compilation
        print_section("Compilation")
        
        # Only compile dwm now (polybar is installed via pacman)
        targets = ["dwm"]
        for target in targets:
            t_path = os.path.join(CONFIG_DIR, target)
            if os.path.exists(t_path):
                console.print(f"   [cyan]➤[/cyan] Compiling [bold]{target}[/bold]...")
                
                # Patch config.mk (Critical for Arch compilation)
                config_mk = os.path.join(t_path, "config.mk")
                if os.path.exists(config_mk):
                    try:
                        with open(config_mk, "r") as f: mk_data = f.read()
                        mk_data = mk_data.replace("/usr/X11R6/include", "/usr/include")
                        mk_data = mk_data.replace("/usr/X11R6/lib", "/usr/lib")
                        if "/usr/include/freetype2" not in mk_data:
                            mk_data = mk_data.replace("FREETYPEINC = /usr/include", "FREETYPEINC = /usr/include/freetype2")
                        with open(config_mk, "w") as f: f.write(mk_data)
                    except: pass

                os.chdir(t_path)
                # Clean install to /usr/local/bin (default)
                exit_code = os.system("sudo make clean install > /dev/null 2>&1")
                
                if exit_code != 0:
                    console.print(Align.center(f"[{C_ERROR}]CRITICAL ERROR: Failed to compile {target}.[/]"))
                    console.print(Align.center("[red]Re-running with output to debug:[/red]"))
                    os.system("sudo make clean install")
                    sys.exit(1)
                    
                os.chdir(os.path.expanduser("~")) # Reset to safe dir
            else:
                console.print(Align.center(f"[yellow]Warning: {target} folder not found.[/yellow]"))

        # .xinitrc creation
        console.print(Align.center("\n[dim]Configuring startup...[/dim]"))
        xinitrc_path = os.path.expanduser("~/.xinitrc")
        
        xinit_content = f"""#!/bin/sh
# =======================================================
# --- guhwm .xinitrc ------------------------------------
# =======================================================

# === Compositor ========================================
picom -b &

# === Polybar ===========================================
# Polybar replaces the built-in dwm bar
# Configuration: ~/.config/polybar/
# To toggle visibility: Alt+B (or your mod key + B)
~/.config/polybar/launch.sh &

# === Notification Daemon ===============================
pino &

# === Hotkey Daemon =====================================
sxhkd &

# === Redshift ==========================================
if command -v redshift >/dev/null 2>&1; then
  TEMP=4000   # Recommended warm color temperature
  if redshift -m randr -O $TEMP >/dev/null 2>&1; then
    redshift -m randr -O $TEMP &
  elif redshift -m vidmode -O $TEMP >/dev/null 2>&1; then
    redshift -m vidmode -O $TEMP &
  else
    redshift -O $TEMP &
  fi
fi

# === guhwall ===========================================
# Restore the Wallust Color Scheme
# wallust stores color sequences in ~/.cache/wallust/sequences
# This applies the last generated color scheme to terminals
cat ~/.cache/wallust/sequences 2>/dev/null &

# Restore the Wallpaper Image
# guhwall uses 'feh' to set wallpapers, which saves a restore script at ~/.fehbg
# This restores the last wallpaper on each login
[ -f ~/.fehbg ] && sh ~/.fehbg &

# --- First Run ---------------------------------
# Launches guhwall only on the very first startup
if [ ! -f ~/.cache/guhwall_first_run ]; then
    mkdir -p ~/.cache
    touch ~/.cache/guhwall_first_run
    # Run guhwall in the background
    guhwall &
fi

# === Keyboard Layouts ==================================
# Uncomment and adjust the next line to enable multiple layouts
# Example: US English, Bulgarian Traditional phonetic, Arabic Macintosh phonetic

# setxkbmap -layout "us,bg,ara" -variant ",phonetic,mac-phonetic" -option "grp:ctrl_space_toggle" &

exec dbus-run-session dwm
"""
        if os.path.exists(xinitrc_path):
            if questionary.confirm(f".xinitrc already exists. Overwrite?").ask():
                shutil.copy(xinitrc_path, f"{xinitrc_path}.bak")
                with open(xinitrc_path, "w") as f: f.write(xinit_content)
        else:
            with open(xinitrc_path, "w") as f: f.write(xinit_content)
        
        os.system(f"chmod +x {xinitrc_path}")
        
        # --- AUTO-START LOGIC (TTY1) ---
        console.print(Align.center("\n[dim]Enabling auto-start on login (TTY1)...[/dim]"))
        
        auto_start_snippet = """
# Auto-start X11 (guhwm) on TTY1
if [ -z "${DISPLAY}" ] && [ "${XDG_VTNR}" -eq 1 ]; then
    exec startx
fi
"""
        for profile in [".bash_profile", ".zprofile", ".profile"]:
            p_path = os.path.expanduser(f"~/{profile}")
            
            if not os.path.exists(p_path):
                with open(p_path, "w") as f: f.write("")
            
            with open(p_path, "r") as f: content = f.read()
            
            if "exec startx" not in content:
                with open(p_path, "a") as f: f.write(auto_start_snippet)
                console.print(f"   [green]✔[/green] [dim]Updated {profile}[/dim]")
        
    else:
        console.print(Align.center(f"[{C_ERROR}]Failed to clone repository.[/]"))

    # 8. Finish
    print_header()
    
    success_msg = Text("\nInstallation Complete!\n", style="bold green", justify="center")
    success_msg.append("\nReboot to launch guhwm.\n", style="white")
    
    console.print(Align.center(Panel(success_msg, border_style="green", box=box.DOUBLE, padding=1)))
    
    if questionary.confirm("Do you want to reboot now?").ask():
        os.system("sudo reboot")
    else:
        console.print("\n[dim]Exiting installer...[/dim]")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nCancelled by user.")
        sys.exit(0)
EOF

# 5. Run
if [ -f "installer.py" ]; then
    python3 installer.py
else
    echo -e "${ROSE}[!] Error: installer.py was not created.${NC}"
fi

# 6. Cleanup
rm -f installer.py
