#!/bin/bash

SLACK_BACKUP_CONFIG=${SLACK_BACKUP_CONFIG:-"config.sh"}
source common.sh
source "$SLACK_BACKUP_CONFIG"

if [[ $SLACK_BACKUP_DEBUG -gt 0 ]]; then
  set -x
fi

c_channel=$1

START_FROM=${START_FROM:-$(cat log/$team_name/*/$c_channel/purge.done 2>/dev/null | sort -r | head -n 1 | awk -F. '{ print $1 }')} # unix timestamp

for f in $(ls -r messages/$team_name/*/$c_channel/); do
  f_ts=$(basename $f | awk -F. '{ print $1 }')
  if [[ "X$f_ts" != "Xlatest" ]]; then
    continue
  fi
  if [[ $f_ts -lt $START_FROM ]]; then
    break
  fi
  f="messages/$team_name/*/$c_channel/$f"
  echo "reading $f"
  t=$(basename $(dirname $(dirname $f)))
  touch log/$team_name/$t/$c_channel/purge.done
  for c_ts in $(jq -r '.messages[].ts' $f | sort -r); do
    if [[ $(grep -c "^$c_ts$" log/$team_name/$t/$c_channel/purge.done) -gt 0 ]]; then
      echo -n -
      continue
    fi
    x_ts=$(gdate +%s.%3N)
    while [[ 1 ]]; do
      make-request "https://$team_name.slack.com/api/chat.delete?_x_id=$x_id-$x_ts&slack_route=$team_id&_x_version_ts=$x_version_ts" \
        --form _x_mode=online \
        --form _x_reason=animateAndDeleteMessageApi \
        --form _x_sonic=true \
        --form channel="${c_channel}" \
        --form token="${token}" \
        --form ts="${c_ts}" \
        >log/$team_name/$t/$c_channel/purge.json 2>log/$team_name/$t/$c_channel/purge.log
      status_code="$(get-response-status-code "log/${team_name}/${t}/${c_channel}/purge.log")"
      if [[ $status_code -eq 200 ]]; then
        echo "$c_ts" >> log/$team_name/$t/$c_channel/purge.done
        echo -n .
        break
      else
        echo -n +
        sleep 1
      fi
    done
  done
  echo
done
exit

