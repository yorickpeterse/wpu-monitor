#!/usr/bin/env fish

set temp_interval 1800
set temp_pending 0
set sleep_interval 60
set heating_enabled true
set heating_last_enabled 0

function log
    # Log messages should go to STDERR.
    echo $argv 1>&2
end

function timestamp
    date +%s
end

function http_get
    curl --fail \
        --show-error \
        --silent \
        --connect-timeout 30 \
        --max-time 30 \
        $argv
end

function disable_heating
    mosquitto_pub -h $MQTT_IP -t $MQTT_TOPIC"/cmd" \
        -m '{ "manual_operation_index": 30, "manual_operation_datatype": 0, "manual_operation_value": 0, "manual_operation_checked": 1 }'
end

function enable_heating
    mosquitto_pub -h $MQTT_IP -t $MQTT_TOPIC"/cmd" \
        -m '{ "manual_operation_index": 30, "manual_operation_datatype": 0, "manual_operation_value": 0, "manual_operation_checked": 0 }'

    # It seems that when rapidly sending these messages they're lost, so we wait
    # a little bit
    log 'Waiting for the WiFi module to process the message'
    sleep 30
    log 'Resetting error status'

    # If we don't explicitly reset the error status, the thermostat will keep
    # complaining about it with an A1-16 error code.
    set attempts 5

    while test $attempts -gt 0
        mosquitto_pub -h $MQTT_IP -t $MQTT_TOPIC"/cmd" \
            -m '{ "manual_operation_index": 37, "manual_operation_datatype": 0, "manual_operation_value": 1, "manual_operation_checked": 0 }'

        log 'Waiting for the WiFi module to reset the status'
        sleep 30
        set data (http_get "http://$ITHO_IP/api.html?get=ithostatus")
        set error (echo $data | jq '.data.ithostatus."Error_found"')

        if test $error -eq 1
            log 'Error status not reset, trying again'
            sleep 30
        else
            log 'Error status reset'
            return
        end

        set attempts (math "$attempts - 1")
    end

    log 'Failed to reset the error status after multiple attempts'
end

function update_temp
    log 'Updating outside temperature'
    set outside_temp (
        http_get 'https://data.buienradar.nl/2.0/feed/json' \
            | jq ".actual.stationmeasurements[] | select(.stationid == $WEATHER_STATION_ID) | .temperature | ceil"
    )
    set itho_data (http_get "http://$ITHO_IP/api.html?get=ithostatus")
    set room_temp (echo $itho_data | jq '.data.ithostatus."Room temp (°C)"')
    set req_room_temp (echo $itho_data | jq '.data.ithostatus."Requested room temp (°C)"')
    set min_temp (math "$req_room_temp - 1.5")
    set hour (date +%H)

    # At night heating is disabled _unless_ it gets too cold. This way heating
    # either doesn't need to run because the morning sun warms up the house, or
    # it can run on the excess solar energy (if there's any).
    if test $hour -ge 0 &&
            test $hour -le 9 &&
            test $room_temp -ge $min_temp &&
            test $outside_temp -ge 0
        # We don't disable heating if we recently re-enabled it, such that we
        # don't ping-pong between enabling and disabling heating.
        if $heating_enabled &&
                test (math (timestamp)" - $heating_last_enabled") -ge 10800
            log "Disabling heating at night, indoor temperature: $room_temp""C, outdoor temperature: $outside_temp"C
            disable_heating
            set heating_enabled false
        end
    else if ! $heating_enabled
        log 'Re-enabling heating'
        enable_heating
        set heating_enabled true
        set heating_last_enabled (timestamp)
    end

    log "New outside temperature: $outside_temp"C
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
    set manual (echo $data | jq '.data.ithostatus."Manual operation"')

    echo "wpu_boiler temp_up=$boiler_temp_up,temp_down=$boiler_temp_down,pump_speed=$boiler_pump_speed
wpu_liquid temp=$liquid_temp,flow_rate=$flow_hour
wpu_source supply_temp=$from_src_temp,return_temp=$to_src_temp,pump_speed=$well_pump_speed
wpu_cv supply_temp=$cv_supply_temp,return_temp=$cv_return_temp,pump_speed=$cv_pump_speed,pressure=$cv_pressure
wpu_room temp=$room_temp,target_temp=$req_room_temp
wpu_outside temp=$outside_temp
wpu status=$system_status,manual_mode=$manual" | ncat --udp $DB_IP $DB_PORT
end

if ! test -n $ITHO_IP
    log 'The ITHO_IP variable must be set'
    exit 1
end

if ! test -n $DB_IP
    log 'The DB_IP variable must be set'
    exit 1
end

if ! test -n $DB_PORT
    log 'The DB_PORT variable must be set'
    exit 1
end

if ! test -n $MQTT_IP
    log 'The MQTT_IP variable must be set'
    exit 1
end

if ! test -n $MQTT_TOPIC
    log 'The MQTT_TOPIC variable must be set'
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
