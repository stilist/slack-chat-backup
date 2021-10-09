#!/bin/bash

SLACK_BACKUP_CONFIG=${SLACK_BACKUP_CONFIG:-"config.sh"}
source common.sh
source "$SLACK_BACKUP_CONFIG"

if [[ $SLACK_BACKUP_DEBUG -gt 0 ]]; then
  set -x
fi

trap "for i in \$(jobs -p); do kill \$i; done; exit" SIGINT SIGHUP

echo "Job manager - start : $MAX_THREADS jobs at a time!"

for c in messages/$team_name/*/*; do
  ( echo "Job started: $c "
  fcount=0
  for f in $c/*.json; do
    channel=$(basename $(dirname $f))
    for a in $(jq -r '.messages[]|select(.files!=null)|.files[]|select(.url_private_download!=null)|.url_private_download' $f); do
      p=$(echo $a | awk -F'slack.com/files-pri/' '{ print $2 }')
      if [[ -z $p ]]; then
        continue
      fi
      mkdir -p files/$team_name/$(dirname $p)
      mkdir -p log/$team_name/$c
      if [[ -f files/$team_name/$p ]]; then
        echo "Job: $c - $a already exists"
        continue
      fi
      while [[ 1 ]]; do
        make-request "$a" \
           >files/$team_name/$p 2>log/$team_name/$c/download_files.log
        status_code="$(get-response-status-code "log/${team_name}/${c}/download_files.log")"
        if [[ $status_code -eq 200 ]]; then
          let fcount=$fcount+1
          echo "Job: $c - $a downloaded OK"
          break
        else
          echo "Job: $c - $a failed. Retrying.."
          sleep 1
        fi
      done
    done
  done
  echo "Job completed: $c - $fcount file(s) downloaded" ) &
  while [[ true ]]; do
    RUNNING=$(jobs | grep -c 'Running')
    if [[ $RUNNING -lt $MAX_THREADS ]]; then
      break
    fi
    sleep 1
  done
done

counter=0
while [[ true ]]; do
  RUNNING=$(jobs | grep -c 'Running')
  if [[ $RUNNING -eq 0 ]]; then
    break
  fi
  if [[ $counter -gt 30 ]]; then
    echo "Job manager - checkpoint : $RUNNING jobs running.."
    counter=0
  fi
  sleep 1
  let counter=$counter+1
done

echo "Job manager - finish : All jobs completed!"
