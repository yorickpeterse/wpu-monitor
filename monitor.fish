#!/usr/bin/env fish

function http_get
    curl --fail \
        --show-error \
        --silent \
        --connect-timeout 30 \
        --max-time 30 \
        $argv
end

function update_temp
    echo 'Updating outside temperature'
    set temp (
        http_get 'https://data.buienradar.nl/2.0/feed/json' \
            | jq ".actual.stationmeasurements[] | select(.stationid == $WEATHER_STATION_ID) | .temperature | ceil"
    )

    http_get "http://$ITHO_IP/api.html?outside_temp=$temp" >/dev/null
    echo "New outside temperature: $temp"C
end

function update_stats
    set data (http_get "http://$ITHO_IP/api.html?get=ithostatus")

    set outside_temp (echo $data | jq '."Outside temp (°C)"')
    set boiler_temp_down (echo $data | jq '."Boiler temp down (°C)"')
    set boiler_temp_up (echo $data | jq '."Boiler temp up (°C)"')
    set liquid_temp (echo $data | jq '."Liquid temp (°C)"')
    set to_src_temp (echo $data | jq '."Temp to source (°C)"')
    set from_src_temp (echo $data | jq '."Temp from source (°C)"')
    set cv_supply_temp (echo $data | jq '."CV supply temp (°C)"')
    set cv_return_temp (echo $data | jq '."CV return temp (°C)"')
    set room_temp (echo $data | jq '."Room temp (°C)"')
    set req_room_temp (echo $data | jq '."Requested room temp (°C)"')

    set cv_pressure (echo $data | jq '."CV pressure (Bar)"')
    set flow_hour (echo $data | jq '."Flow sensor (lt_hr)"')
    set cv_pump_speed (echo $data | jq '."Cv pump (%)"')
    set well_pump_speed (echo $data | jq '."Well pump (%)"')
    set boiler_pump_speed (echo $data | jq '."Boiler pump (%)"')
    set system_status (echo $data | jq '."Status"')

    echo "wpu_boiler temp_up=$boiler_temp_up,temp_down=$boiler_temp_down,pump_speed=$boiler_pump_speed
wpu_liquid temp=$liquid_temp,flow_rate=$flow_hour
wpu_source supply_temp=$from_src_temp,return_temp=$to_src_temp,pump_speed=$well_pump_speed
wpu_cv supply_temp=$cv_supply_temp,return_temp=$cv_return_temp,pump_speed=$cv_pump_speed,pressure=$cv_pressure
wpu_room temp=$room_temp,target_temp=$req_room_temp
wpu_outside temp=$outside_temp
wpu status=$system_status" | ncat --udp $DB_IP $DB_PORT
end

if ! test -n "$ITHO_IP"
    echo 'The ITHO_IP variable must be set'
    exit 1
end

if ! test -n "$DB_IP"
    echo 'The DB_IP variable must be set'
    exit 1
end

if ! test -n "$DB_PORT"
    echo 'The DB_PORT variable must be set'
    exit 1
end

set temp_interval 3600
set temp_pending 0
set sleep_interval 60

while true
    if test -n "$WEATHER_STATION_ID"
        if test $temp_pending -eq 0
            set temp_pending (math "$temp_interval / $sleep_interval")
            update_temp
        else
            set temp_pending (math "$temp_pending - 1")
        end
    end

    update_stats
    sleep $sleep_interval
end
