#!/bin/bash

source common.sh
source "$SLACK_BACKUP_CONFIG"

if [[ $SLACK_BACKUP_DEBUG -gt 0 ]]; then
  set -x
fi

# try to get new cookie from server
mkdir -p cookies
if [[ ! -f "cookies/$team_name.jar" ]]; then
  echo "# generated by t-tran/slack-chat-backup" > "cookies/$team_name.jar"
  for c in $(echo $cookie | sed -e 's/;/ /g'); do
    c=$(echo $c | awk -F= '{print $1"\t"$2}')
    echo -e ".slack.com\tTRUE\t/\tTRUE\t0\t$c" >> "cookies/$team_name.jar"
  done
  curl -svL "https://$team_name.slack.com/" \
  -H "User-Agent: $USER_AGENT" \
  -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8' \
  -H 'Accept-Language: en-US,en;q=0.5' \
  -H 'Upgrade-Insecure-Requests: 1' --cookie "cookies/$team_name.jar" --cookie-jar "cookies/$team_name.jar" \
  >/dev/null 2>/dev/null
fi

x_version_ts=${x_version_ts:-$(date +%s)}
x_id=${x_id:-$(echo $x_version_ts | md5sum | cut -c -8)}
x_ts=$(gdate +%s.%3N)
boundary='---------------------------'$(generate-digits 29)

mkdir -p meta/$team_name
mkdir -p log/$team_name
echo "Loading my own profile.."
attempt=1
while [[ true ]]; do
  curl -sv "https://$team_name.slack.com/api/client.boot?_x_id=noversion-$x_ts&_x_version_ts=noversion&_x_gantry=true" \
  -H "User-Agent: $USER_AGENT" \
  -H 'Accept: */*' -H 'Accept-Language: en-US,en;q=0.5' \
  -H 'Content-Type: multipart/form-data; boundary='$boundary \
  -H 'Origin: https://app.slack.com' \
  -H 'Cache-Control: max-age=0' \
  --cookie "cookies/$team_name.jar" \
  --data-binary $'--'$boundary$'\r\nContent-Disposition: form-data; name="token"\r\n\r\n'$token$'\r\n--'$boundary$'\r\nContent-Disposition: form-data; name="only_self_subteams"\r\n\r\n1\r\n--'$boundary$'\r\nContent-Disposition: form-data; name="flannel_api_ver"\r\n\r\n4\r\n--'$boundary$'\r\nContent-Disposition: form-data; name="include_min_version_bump_check"\r\n\r\n1\r\n--'$boundary$'\r\nContent-Disposition: form-data; name="version_ts"\r\n\r\n'$x_version_ts$'\r\n--'$boundary$'\r\nContent-Disposition: form-data; name="_x_reason"\r\n\r\ndeferred-data\r\n--'$boundary$'\r\nContent-Disposition: form-data; name="_x_sonic"\r\n\r\ntrue\r\n--'$boundary$'--\r\n' \
  >meta/$team_name/boot.json 2>log/$team_name/boot.log

  status_code=$(cat log/$team_name/boot.log | grep "^< HTTP/" | awk '{ print $3 }')
  if [[ $status_code -ne 200 ]]; then
    # try again
    if [[ $status_code -eq 429 ]]; then
      echo "Rate-limited. Re-trying.."
      sleep 3
    else
      echo "Non-OK code. Re-trying.."
    fi
    sleep 1
  else
    if [[ $(jq .self meta/$team_name/boot.json) == "null" ]]; then
      echo "Invalid json result. Re-trying.."
      if [[ $attempt -gt 3 ]]; then
        echo "Max retries exceeded. Maybe a bad cookie jar at 'cookies/$team_name.jar'? Try deleting it!"
        exit 1
      fi
      let attempt=$attempt+1
    else
      break
    fi
  fi
done

mkdir -p meta/$team_name/users
mkdir -p log/$team_name/meta/users
for i in $(cat meta/$team_name/boot.json | jq .| grep '"U' | tr -d '":,'); do  if [[ "X$i" == "XU"* ]]; then echo $i; fi; done | sort | uniq | grep -v Used > meta/$team_name/users.txt
for u in $(cat meta/$team_name/users.txt); do
  echo -n "Loading user profile '$u' .."
  while [[ true ]]; do
    curl -sv "https://edgeapi.slack.com/cache/T027BCF4R/users/info" \
    -H "User-Agent: $USER_AGENT" \
    -H 'Accept: */*' \
    -H 'Accept-Language: en-US,en;q=0.5' \
    -H 'Content-Type: application/json' \
    -H 'Origin: https://app.slack.com' \
    -H 'DNT: 1' \
    -H 'Connection: keep-alive' \
    --cookie "cookies/$team_name.jar" \
    --data '{"token":"'$token'","check_interaction":true,"updated_ids":{"'$u'":0}}' \
    >meta/$team_name/users/$u.json 2>log/$team_name/meta/users/$u.log

    status_code=$(cat log/$team_name/meta/users/$u.log | grep "^< HTTP/" | awk '{ print $3 }')
    if [[ $status_code -ne 200 ]]; then
      # try again
      if [[ $status_code -eq 429 ]]; then
        echo -n s
        sleep 3
      else
        echo -n x
      fi
      sleep 1
    else
      info=$(jq -r '.results[0]|"\(.name) | \(.profile.real_name) | \(.profile.title)"' meta/$team_name/users/$u.json)
      if [[ $? -gt 0 ]]; then
        echo -n j
      else
        echo -n ". $info"
        break
      fi
    fi
  done
  echo
done
