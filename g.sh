#!/usr/bin/env bash

# ──────────────────────────────────────────────────────────────────────────────
#  AVIE — CLI Sentinel Fetch (Fixed Alignment & Wrapping)
# ──────────────────────────────────────────────────────────────────────────────

# ── Configuration ─────────────────────────────────────────────────────────────
STRIPE_W=24  
INFO_W=35     # Increased to accommodate SwiftPM text
GUTTER=3
TOTAL_BLOCK_W=$((STRIPE_W + GUTTER + INFO_W))

# ── Terminal Check & Centering ────────────────────────────────────────────────
TERM_COLS=$(tput cols)
if [ "$TERM_COLS" -lt "$TOTAL_BLOCK_W" ]; then
    echo -e "\n\033[31m[!] Error: Terminal width ($TERM_COLS) is too narrow.\033[0m"
    exit 1
fi

PAD_VAL=$(( (TERM_COLS - TOTAL_BLOCK_W) / 2 ))
PAD_L=$(printf "%${PAD_VAL}s" "")

# ── Colors ────────────────────────────────────────────────────────────────────
R="\033[0m"
FB="\033[48;2;76;93;109m"    # Fabric: Blue-Grey
FF="\033[38;2;55;70;84m"
NB="\033[48;2;19;28;75m"    # Dark Navy Stripe
SB="\033[48;2;122;178;211m"  # Sky Blue Stripe
SF="\033[38;2;88;145;175m"
BOLD="\033[1m"
LBLUE="\033[38;2;122;178;211m"
WHITE="\033[97m"
GRAY="\033[38;2;160;175;185m"

# ── System Data ───────────────────────────────────────────────────────────────
OS_NAME="$(uname -s) $(uname -m)"
KERNEL="$(uname -r)"
SHELL_NAME="$(basename "$SHELL")"
UPTIME_STR="$(uptime -p 2>/dev/null | sed 's/up //')"
PKG_COUNT="0 (SwiftPM)" # Dynamic count logic goes here

# ── Rendering Logic ───────────────────────────────────────────────────────────
render_line() {
    local stripe_color="$1"
    local stripe_content="$2"
    local label="$3"
    local value="$4"
    
    # 1. Left Column: Insignia (No extra spaces outside the color block)
    printf "${PAD_L}${stripe_color}%-${STRIPE_W}s${R}" "$stripe_content"
    
    # 2. Gutter
    printf "%${GUTTER}s" ""
    
    # 3. Right Column: System Info (Truncated to prevent wrapping)
    if [ -n "$label" ]; then
        local max_info_w=$((INFO_W - ${#label} - 2))
        local clean_val="${value:0:$max_info_w}"
        printf "${LBLUE}${BOLD}%s${R} ${WHITE}%s${R}\n" "$label:" "$clean_val"
    else
        printf "\n"
    fi
}

# Define Patterns
W_SOLID=" "
W_DOTS=$(printf "· %.0s" $(seq 1 $((STRIPE_W/2))))

# ── Output ────────────────────────────────────────────────────────────────────
clear
echo -e "\n"

# Fixed Title Rendering
TITLE_STR="avie@sentinel"
printf "${PAD_L}%$(( (TOTAL_BLOCK_W / 2) + (${#TITLE_STR} / 2) ))s\n" "${LBLUE}${BOLD}${TITLE_STR}${R}"
printf "${PAD_L}${GRAY}%${TOTAL_BLOCK_W}s${R}\n" | tr " " "─"
echo ""

# Block Execution - Fixed sequence to remove the gap
render_line "$FB$FF" "$W_DOTS"  "" ""
render_line "$FB$FF" "$W_DOTS"  "OS"       "placeholder"
render_line "$NB"    "$W_SOLID" "Kernel"   "placeholder"
render_line "$NB"    "$W_SOLID" "Uptime"   "placeholder"
render_line "$FB$FF" "$W_SOLID" "Shell"    "placeholder"
render_line "$SB$SF" "$W_DOTS"  "Packages" "placeholder"
render_line "$FB$FF" "$W_SOLID" "Project"  "placeholder"
render_line "$NB"    "$W_SOLID" "Rank"     "placeholder"
render_line "$NB"    "$W_SOLID" "Status"   "placeholder"
render_line "$FB$FF" "$W_DOTS"  "" ""
render_line "$FB$FF" "$W_DOTS"  "" ""

echo ""
printf "${PAD_L}${GRAY}%${TOTAL_BLOCK_W}s${R}\n" | tr " " "─"
echo -e "\n"