#!/bin/bash

mkdir -p meta messages files log

make-request() {
  curl \
    --silent \
    --verbose \
    --cookie "cookies/${team_name:?}.jar" \
    --header "Accept-Language: en-US,en;q=0.5" \
    --header "Accept: */*" \
    --header "Origin: https://app.slack.com" \
    --header "User-Agent: ${USER_AGENT:?}" \
    "${@}"
}

make-paginated-request() {
  local page_count
  page_count="$(
    make-request "${@}" \
      | jq ".pagination.page_count"
  )"

  local request
  request="${*}"
  for page in $(seq "${page_count}") ; do
    make-request ${request} \
      --form page="${page}"
    echo
  done
}

get-response-status-code() {
  local log_path
  log_path="${1}"

  grep "^< HTTP/" "${log_path}" \
    | tail -1 \
    | awk '{ print $3 }'
}

function generate-digits() {
  local S=''
  for i in $(seq 1 "$1") ; do
    S="$S$(( RANDOM % 10 ))"
  done
  echo $S
}

if [ "$(uname)" = "Linux" ] &&
    ! command -v gdate >/dev/null &&
    command -v date >/dev/null; then

    gdate() {
        date "$@"
    }
fi
