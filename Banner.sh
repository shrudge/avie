#!/usr/bin/env bash

# ──────────────────────────────────────────────────────────────────────────────
#  AVIE — CLI Sentinel Fetch (Fixed Alignment & Wrapping)
# ──────────────────────────────────────────────────────────────────────────────

# ── Configuration ─────────────────────────────────────────────────────────────
STRIPE_W=24  
INFO_W=35     # Increased to accommodate SwiftPM text
GUTTER=3
TOTAL_BLOCK_W=82

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
NAVY="\033[38;2;19;28;75m"   # Navy Blue foreground
WHITE="\033[97m"
GRAY="\033[38;2;160;175;185m"

# ── System Data ───────────────────────────────────────────────────────────────
OS_NAME="$(uname -s) $(uname -m)"
KERNEL="$(uname -r)"
SHELL_NAME="$(basename "$SHELL")"
# Define Patterns
W_SOLID=$(printf "%24s" " ")
W_DOTS=$(printf "%24s" " ") # Removed dots as requested

# ── Rendering Logic ───────────────────────────────────────────────────────────
# ── Rendering Logic ───────────────────────────────────────────────────────────
# We now render the insignia and word mark side-by-side.
# Fixed padding for stability across different terminal environments.
FIXED_PAD="               " # 15 spaces

# Insignia lines
L0="${FB}${FF}${W_DOTS}${R}"
L1="${FB}${FF}${W_DOTS}${R}"
L2="${NB}${W_SOLID}${R}"
L3="${NB}${W_SOLID}${R}"
L4="${FB}${FF}${W_SOLID}${R}"
L5="${SB}${SF}${W_DOTS}${R}"
L6="${FB}${FF}${W_SOLID}${R}"
L7="${NB}${W_SOLID}${R}"
L8="${NB}${W_SOLID}${R}"
L9="${FB}${FF}${W_DOTS}${R}"
L10="${FB}${FF}${W_DOTS}${R}"

# Word mark lines (NAVY) - 7-Line Block Style
W_A0="  █████   █     █  █████  ███████ "
W_A1=" █     █  █     █    █    █       "
W_A2=" █     █  █     █    █    █       "
W_A3=" ███████  █     █    █    ██████  "
W_A4=" █     █   █   █     █    █       "
W_A5=" █     █    █ █      █    █       "
W_A6=" █     █     █     █████  ███████ "

# ── Output ────────────────────────────────────────────────────────────────────
# We use a single format string to ensure the terminal respects all leading whitespace
# and interprets the entire block as a single unit, preventing first-line misalignment.

LOGO_FORMAT="\n"
LOGO_FORMAT+="               %b    \n"                             # L0
LOGO_FORMAT+="               %b    \n"                             # L1
LOGO_FORMAT+="               %-24b    ${NAVY}${BOLD}%s${R}\n" # L2 + W0
LOGO_FORMAT+="               %-24b    ${NAVY}${BOLD}%s${R}\n" # L3 + W1
LOGO_FORMAT+="               %-24b    ${NAVY}${BOLD}%s${R}\n" # L4 + W2
LOGO_FORMAT+="               %-24b    ${NAVY}${BOLD}%s${R}\n" # L5 + W3
LOGO_FORMAT+="               %-24b    ${NAVY}${BOLD}%s${R}\n" # L6 + W4
LOGO_FORMAT+="               %-24b    ${NAVY}${BOLD}%s${R}\n" # L7 + W5
LOGO_FORMAT+="               %-24b    ${NAVY}${BOLD}%s${R}\n" # L8 + W6
LOGO_FORMAT+="               %b    \n"                             # L9
LOGO_FORMAT+="               %b    \n"                             # L10
LOGO_FORMAT+="\n"
LOGO_FORMAT+="                   ${GRAY}Swift package graph diagnostics & audit tool.${R}\n"
LOGO_FORMAT+="                   ${GRAY}Version ${WHITE}placeholder${R}${GRAY} • Graph-provable findings.${R}\n\n"

printf "${LOGO_FORMAT}" \
    "${L0}" "${L1}" \
    "${L2}" "${W_A0}" \
    "${L3}" "${W_A1}" \
    "${L4}" "${W_A2}" \
    "${L5}" "${W_A3}" \
    "${L6}" "${W_A4}" \
    "${L7}" "${W_A5}" \
    "${L8}" "${W_A6}" \
    "${L9}" "${L10}"