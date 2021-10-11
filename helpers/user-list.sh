#!/bin/bash

##
# Extract users from `boot.json`--this may include some deactivated users.
##
user-list-boot-json() {
  jq --raw-output \
    "
      .self.id,
      (.channels[] | .creator, .purpose.creator, .topic.creator),
      .ims[].user,
      .mpims[].members[]
    " \
    "${SLACK_BACKUP_ROOT:?}/meta/${team_name:?}/boot.json"
}

##
# Search for deactivated users.
##
user-list-deactivated() {
  local output_file
  output_file="${SLACK_BACKUP_ROOT:?}/meta/${team_name:?}/deactivated-users.json"

  # account types:
  # 1 - all types
  # 2 - owners
  # 3 - admins
  # 4 - full members
  # 5 - guests
  # 6 - deactivated
  make-paginated-request "https://${team_name:?}.slack.com/api/search.modules?_x_id=${x_id:?}-${x_ts:?}&slack_route=${team_id:?}&_x_version_ts=${x_version_ts:?}&_x_gantry=true" \
    --form _x_mode="online" \
    --form _x_reason="browser-query" \
    --form _x_sonic="true" \
    --form account_type=6 \
    --form browse="standard" \
    --form count=500 \
    --form custom_fields="{}" \
    --form extra_message_data=1 \
    --form extracts=0 \
    --form hide_deactivated_users=0 \
    --form highlight=0 \
    --form max_filter_suggestions=10 \
    --form module="people" \
    --form no_user_profile=1 \
    --form query="" \
    --form sort_dir="asc" \
    --form sort="name" \
    --form team="${team_id:?}" \
    --form token="${token:?}" \
    >"${output_file}" \
    2>"${SLACK_BACKUP_ROOT:?}/log/${team_name:?}/boot.log"
  jq --raw-output \
    ".items[].id" \
    "${output_file}"
}

##
# Fetch list of active users in general channel.
##
user-list-general-channel() {
  local output_file
  output_file="${SLACK_BACKUP_ROOT:?}/meta/${team_name:?}/users.json"

  general_channel_id="$(
    jq --raw-output \
      ".channels[] | select(.is_general==true) | .id" \
      "${SLACK_BACKUP_ROOT:?}/meta/${team_name:?}/boot.json"
  )"
  make-request "https://edgeapi.slack.com/cache/${team_id:?}/users/list" \
    --header "Content-Type: application/json" \
    --data "{\"token\":\"${token:?}\",\"channels\":[\"${general_channel_id}\"],\"filter\":\"everyone AND NOT bots AND NOT apps\",\"count\":500}" \
    >"${output_file}" \
    2>"${SLACK_BACKUP_ROOT:?}/log/${team_name:?}/general-channel-users.log"
  jq --raw-output \
    ".results[].id" \
    "${output_file}"
}

##
# Build a list of users in the Slack. Note that this may be missing some
# deactivated users.
##
user-list() {
  local temporary_file
  temporary_file="${SLACK_BACKUP_ROOT:?}/meta/${team_name:?}/users.txt"

  {
    user-list-boot-json
    user-list-deactivated
    user-list-general-channel
  } >"${temporary_file}"

  # sort and remove blank line
  sort --unique "${temporary_file}" \
    | awk NF
}
