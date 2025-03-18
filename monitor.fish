#!/usr/bin/env fish

set temp_interval 3600
set temp_pending 0
set sleep_interval 60
set override_temp 20

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
    set outside_temp (
        http_get 'https://data.buienradar.nl/2.0/feed/json' \
            | jq ".actual.stationmeasurements[] | select(.stationid == $WEATHER_STATION_ID) | .temperature | ceil"
    )
    set itho_data (http_get "http://$ITHO_IP/api.html?get=ithostatus")
    set room_temp (echo $itho_data | jq '.data.ithostatus."Room temp (°C)"')
    set req_room_temp (echo $itho_data | jq '.data.ithostatus."Requested room temp (°C)"')
    set min_temp (math "$req_room_temp - 0.5")
    set hour (date +%H)

    # At night we try to defer heating by reporting a higher outdoor
    # temperature, provided it's not getting too cold.
    if test $hour -ge 2 &&
            test $hour -le 8 &&
            test $room_temp -ge $min_temp &&
            test $outside_temp -ge -5 &&
            test $outside_temp -le 15
        echo "Overriding outside temperature to $override_temp""C, real temperature: $outside_temp"C
        set outside_temp $override_temp
    else
        echo "New outside temperature: $outside_temp"C
    end

    http_get "http://$ITHO_IP/api.html?outside_temp=$outside_temp" >/dev/null
end

function update_stats
    set data (http_get "http://$ITHO_IP/api.html?get=ithostatus")

    set outside_temp (echo $data | jq '.data.ithostatus."Outside temp (°C)"')
    set boiler_temp_down (echo $data | jq '.data.ithostatus."Boiler temp down (°C)"')
    set boiler_temp_up (echo $data | jq '.data.ithostatus."Boiler temp up (°C)"')
    set liquid_temp (echo $data | jq '.data.ithostatus."Liquid temp (°C)"')
    set to_src_temp (echo $data | jq '.data.ithostatus."Temp to source (°C)"')
    set from_src_temp (echo $data | jq '.data.ithostatus."Temp from source (°C)"')
    set cv_supply_temp (echo $data | jq '.data.ithostatus."CV supply temp (°C)"')
    set cv_return_temp (echo $data | jq '.data.ithostatus."CV return temp (°C)"')
    set room_temp (echo $data | jq '.data.ithostatus."Room temp (°C)"')
    set req_room_temp (echo $data | jq '.data.ithostatus."Requested room temp (°C)"')

    set cv_pressure (echo $data | jq '.data.ithostatus."CV pressure (Bar)"')
    set flow_hour (echo $data | jq '.data.ithostatus."Flow sensor (lt_hr)"')
    set cv_pump_speed (echo $data | jq '.data.ithostatus."Cv pump (%)"')
    set well_pump_speed (echo $data | jq '.data.ithostatus."Well pump (%)"')
    set boiler_pump_speed (echo $data | jq '.data.ithostatus."Boiler pump (%)"')
    set system_status (echo $data | jq '.data.ithostatus."Status"')

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
