#!/usr/bin/env fish

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
    set data (
        curl --fail \
            --show-error \
            --silent \
            --connect-timeout 30 \
            --max-time 30 \
            "http://$ITHO_IP/api.html?get=ithostatus"
    )

    set boiler_temp_down (echo $data | jq '."Boiler temp down (°C)"')
    set boiler_temp_up (echo $data | jq '."Boiler temp up (°C)"')
    set liquid_temp (echo $data | jq '."Liquid temp (°C)"')
    set to_src_temp (echo $data | jq '."Temp to source (°C)"')
    set from_src_temp (echo $data | jq '."Temp from source (°C)"')
    set cv_supply_temp (echo $data | jq '."CV supply temp (°C)"')
    set cv_return_temp (echo $data | jq '."CV return temp (°C)"')
    set room_temp (echo $data | jq '."Room temp (°C)"')

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
wpu_room temp=$room_temp
wpu status=$system_status" | ncat --udp $DB_IP $DB_PORT
    sleep 30
end
