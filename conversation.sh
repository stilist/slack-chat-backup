#!/bin/bash

source common.sh
source "$SLACK_BACKUP_CONFIG"

if [[ $SLACK_BACKUP_DEBUG -gt 0 ]]; then
  set -x
fi

if [[ $# -lt 1 ]]; then
  exit
fi

t=$1
shift

download_files=${DOWNLOAD_FILES:-1}

x_version_ts=${x_version_ts:-$(date +%s)}
x_id=${x_id:-$(echo $x_version_ts | md5sum | cut -c -8)}

ignored_ids=""
if [[ "X$t" == "Xims" ]]; then
  ignored_ids=$ims_ignored
fi
if [[ "X$t" == "Xmpims" ]]; then
  ignored_ids=$mpims_ignored
fi
if [[ "X$t" == "Xchannels" ]]; then
  ignored_ids=$channels_ignored
fi

for i in $@; do
  ignore_matched=0
  cleanup_matched=0
  for a in $ignored_ids; do
    if [[ "X$i" == "X$a" ]]; then
      ignore_matched=1
      break
    fi
  done
  for a in $chats_cleanup; do
    if [[ "X$i" == "X$a" ]]; then
      cleanup_matched=1
      break
    fi
  done
  if [[ $ignore_matched -gt 0 ]]; then
    echo "$t - $i : job skipped!"
    continue
  fi
  echo "$t - $i : job started!"

  latest=''

  mkdir -p messages/$team_name/$t/$i
  mkdir -p log/$team_name/$t/$i
  output=latest
  has_more=true

  while [[ "X$has_more" == "Xtrue" ]]; do
    x_ts=$(gdate +%s.%3N)
    make-request "https://$team_name.slack.com/api/conversations.history?_x_id=$x_id-$x_ts&slack_route=$team_id&_x_version_ts=$x_version_ts" \
      --form _x_mode=online \
      --form _x_reason=message-pane/requestHistory \
      --form _x_sonic=true \
      --form channel="${i}" \
      --form ignore_replies=true \
      --form include_pin_count=true \
      --form inclusive=true \
      --form latest="${latest}" \
      --form limit=42 \
      --form no_user_profile=true \
      --form token="${token}" \
      >messages/$team_name/$t/$i/$output.json 2>log/$team_name/$t/$i/$output.log
    status_code="$(get-response-status-code "log/${team_name}/${t}/${i}/${output}.log")"
    if [[ $status_code -ne 200 ]]; then
      # try again
      if [[ $status_code -eq 429 ]]; then
        echo "$t - $i : $output .. rate-limited. re-trying..."
        sleep 3
      else
        echo "$t - $i : $output .. non-200 code. re-trying..."
      fi
      sleep 0.2
    else
      jq . messages/$team_name/$t/$i/$output.json >/dev/null 2>&1
      if [[ $? -gt 0 ]] || [[ ! -s messages/$team_name/$t/$i/$output.json ]]; then
        echo "$t - $i : $output .. invalid json. re-trying..."
      else
        echo "$t - $i : $output .. ok"
        if [[ $cleanup_matched -gt 0 ]]; then # delete the messages on this channel
          c_channel=$i
          touch log/$team_name/$t/$c_channel/purge.done
          for c_ts in $(jq -r '.messages[].ts' messages/$team_name/$t/$i/$output.json | sort -r); do
            if [[ $(grep -c "^$c_ts$" log/$team_name/$t/$c_channel/purge.done) -gt 0 ]]; then
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
                >messages/$team_name/$t/$i/purge.json 2>log/$team_name/$t/$i/purge.log

              status_code="$(get-response-status-code "log/${team_name}/${t}/${i}/purge.log")"
              if [[ $status_code -eq 200 ]]; then
                echo "$c_ts" >> log/$team_name/$t/$i/purge.done
                break
              else
                sleep 1
              fi
            done
          done
        fi
        if [[ $download_files -gt 0 ]]; then
          for a in $(jq -r '.messages[]|select(.files!=null)|.files[]|select(.url_private_download!=null)|.url_private_download' messages/$team_name/$t/$i/$output.json); do
            p=$(echo $a | awk -F'slack.com/files-pri/' '{ print $2 }')
            if [[ -z $p ]]; then
              continue
            fi
            mkdir -p files/$team_name/$(dirname $p)
            mkdir -p log/$team_name/$(dirname $p)
            if [[ -f files/$team_name/$p ]]; then
              continue
            fi
            while [[ 1 ]]; do
              make-request "$a" \
                 >files/$team_name/$p 2>log/$team_name/$(dirname $p)/download_files.log
              status_code="$(get-response-status-code "log/${team_name}/$(dirname "${p}")/download_files.log")"
              if [[ $status_code -eq 200 ]]; then
                break
              else
                sleep 1
              fi
            done
          done
        fi
        newest=$(basename $(ls -1 messages/$team_name/$t/$i/ 2>/dev/null | sort | grep "$output.json" -B1 | head -n 1) .json || echo 0)
        has_more=$(cat messages/$team_name/$t/$i/$output.json | jq -r .has_more)
        latest=$(cat messages/$team_name/$t/$i/$output.json | jq -r '.messages[].ts' | sort -n | head -n 1)
        output=$latest
        newest_done=0
        if [[ "X$newest" > "X$output" ]] || [[ "X$newest" == "X$output" ]]; then
          newest_done=1
        fi
        if [[ $newest_done -gt 0 ]]; then
          if [[ $SYNC_INCREMENTAL -gt 0 ]]; then
            # point $newest to the oldest timestamp to see if there's stuff we haven't loaded
            newest=$(basename $(ls -1 messages/$team_name/$t/$i/ 2>/dev/null | sort | head -n 1) .json || echo 0)
          fi
          while [[ true ]]; do
            oldest=$(cat messages/$team_name/$t/$i/$newest.json | jq -r '.messages[].ts' | sort -n | head -n 1)
            has_more=$(cat messages/$team_name/$t/$i/$newest.json | jq -r .has_more)
            if [[ ! -f messages/$team_name/$t/$i/$oldest.json ]]; then
              break
            fi
            if [[ "X$has_more" == "Xfalse" ]]; then
              break
            fi
            newest=$oldest
          done
          if [[ "X$has_more" == "Xfalse" ]]; then
            break
          fi
          if [[ ! -f messages/$team_name/$t/$i/$oldest.json ]]; then
            has_more=$(cat messages/$team_name/$t/$i/$newest.json | jq -r .has_more)
            latest=$(cat messages/$team_name/$t/$i/$newest.json | jq -r '.messages[].ts' | sort -n | head -n 1)
            output=$latest
          fi
        fi
      fi
      sleep 0.001
    fi
  done
  echo "$t - $i : job done!"
done

