#!/bin/bash
# shellcheck disable=SC2154
# shellcheck disable=SC2034
# shellcheck disable=SC2059

source "$CYBR_DEMOS_PATH/demos/utility/ubuntu/ansi_colors.sh"

print_line() {
  columns=$(tput cols)

  for i in $(seq 1 "$columns"); do printf "${Black}\u2500${Color_Off}"; done; printf "\n\n"
}

print_prompt() {
printf -- "${Cyan}prompt${Color_Off}$ $1 \n"
}
