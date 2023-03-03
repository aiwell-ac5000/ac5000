#!/bin/bash
PRODUCTION_PORTAL_ADDRESS="213.192.95.198"
PRODUCTION_PORTAL_PORT="8080"
MAC_ADDRESS=""
CUSTOMER_ID=""

get_data_from_json()
{
    is_exist=$(  echo $1 | grep $2 )
    data=""
    if [ -n "$is_exist" ];then
        data=$( echo $1 | python -c "import sys, json; print(json.load(sys.stdin)['$2'])" )
        return 0
    fi
    return 1
}

#$1 -> board_id from eprom/nvram
get_basic_data_from_production_portal()
{
    if ping_command $PRODUCTION_PORTAL_ADDRESS;then
        logging -debug "Connection with production server exist"    
        readDeviceInformation=$( curl -s -S http://${PRODUCTION_PORTAL_ADDRESS}:${PRODUCTION_PORTAL_PORT}/api/v3/index.php/x500/box_id/${1} )
        if [ $readDeviceInformation != "{}" ];then
            ifWrognAnswer=$( echo $readDeviceInformation | grep "400 Bad Request" )
            if [ -z "$ifWrognAnswer" ];then
                if [ "$readDeviceInformation" == "null" ] || [ "$readDeviceInformation" == "Function not supported!" ] || [ -z "$readDeviceInformation" ] ;then
                    logging -err "BOARD_ID not found in production API"
                    return 1
                else  
                    MAC_ADDRESS=$( echo $readDeviceInformation | python -c "import sys, json; print(json.load(sys.stdin)['unique_id_pcb'])" )
                    CUSTOMER_ID=$( echo $readDeviceInformation | python -c "import sys, json; print(json.load(sys.stdin)['customer_id'])" )
                    logging -debug "Found BOARD_ID in production API" 
                    return 0
                fi
            else
                logging -err "BOARD_ID not found in production API"
                return 1
            fi
        else
            logging -err "BOARD_ID not found in production API"
            return 1
        fi
    else
        logging -err "No connection with production server"     
        return 1
    fi
}

#$1 -> BOARD_ID
#$2 -> MAC_ADRESS
get_rest_data_from_production_portal_by_log()
{
    if ping_command $PRODUCTION_PORTAL_ADDRESS;then
        logging -debug "Connection with production server exist"    
        if [ -n "$BOARD_ID" ];then
            readDeviceInformation=$( curl -s -S http://${PRODUCTION_PORTAL_ADDRESS}:${PRODUCTION_PORTAL_PORT}/api/v3/index.php/x500/device_info/${1}/${2} )
            if [ "$readDeviceInformation" != "{}" ];then
                ifWrognAnswer=$( echo $readDeviceInformation | grep "400 Bad Request" )
                if [ -z "$ifWrognAnswer" ];then
                    if [ "$readDeviceInformation" == "null" ] || [ "$readDeviceInformation" == "Function not supported!" ] || [ -z "$readDeviceInformation" ] ;then
                        logging -err "DEVICE INFORMATION FROM LOG not found in production API"
                        return 1
                    else  
                        status=$( echo $readDeviceInformation | python -c "import sys, json; print(json.load(sys.stdin)['status'])" )
                        if [ "$status" == "True" ];then
                            MODEL=$( echo $readDeviceInformation | python -c "import sys, json; print(json.load(sys.stdin)['MODEL'])" )
                            CUSTOMER_ID=$( echo $readDeviceInformation | python -c "import sys, json; print(json.load(sys.stdin)['ID'])" )
                            TESTER=$( echo $readDeviceInformation | python -c "import sys, json; print(json.load(sys.stdin)['TESTER'])" )
                            DATA=$( echo $readDeviceInformation | python -c "import sys, json; print(json.load(sys.stdin)['DATA'])" )
                            CONFIG=$( echo $readDeviceInformation | python -c "import sys, json; print(json.load(sys.stdin)['CONFIG(BRANCH)'])" )
                            iMC=$( echo $readDeviceInformation | python -c "import sys, json; print(json.load(sys.stdin)['iMC-pass'])" )
                            if get_data_from_json $readDeviceInformation "ExCard1";then
                                ExCard1=$data
                            else
                                ExCard1=""
                            fi
                            if get_data_from_json $readDeviceInformation "ExCard2";then
                                ExCard2=$data
                            else
                                ExCard2=""
                            fi
                            if get_data_from_json $readDeviceInformation "ExCard3";then
                                ExCard3=$data
                            else
                                ExCard3=""
                            fi
                            logging -norm "Found DEVICE INFORMATION in production API" 
                            logging -norm "MODEL: $MODEL" 
                            logging -norm "CUSTOMER_ID: $CUSTOMER_ID" 
                            logging -norm "TESTER: $TESTER" 
                            logging -norm "DATA: $DATA" 
                            logging -norm "CONFIG(BRANCH): $CONFIG" 
                            logging -norm "iMC-pass: $iMC" 
                            logging -norm "ExCard1: $ExCard1" 
                            logging -norm "ExCard2: $ExCard2" 
                            logging -norm "ExCard3: $ExCard3" 
                            return 0
                        else
                            logging -err "DEVICE INFORMATION FROM LOG - invalid MAC/BOARD_ID"
                            return 1
                        fi
                    fi
                else
                    logging -err "DEVICE INFORMATION FROM LOG - not found in production API"
                    return 1
                fi
            else
                logging -err "DEVICE INFORMATION FROM LOG - not found in production API"
                return 1
            fi
        else
            logging -err "CAN'T FIND BOARD_ID SO IS NOT POSSIBLE TO DOWNLOAD REST DATA FROM PRODUCTION PORTAL"
            return 1
        fi
    else
        logging -err "No connection with production server"     
        return 1
    fi
}

parse_model()
{
    parse_number_exist=$( echo $1 | grep -o ".*-" | wc -l )
    if [ $parse_number_exist -eq 1 ];then
        return 0
    else
        logging -err "MAC_ADDRESS format is invalid" 
        return 1
    fi
}

save_res_data()
{
    STATE="SAVE_REST_DATA_BY_SETENV"
    logging -info "Save additional data from production portal to env"
    setenv NPE_MODEL "$MODEL"
	setenv NPE_ID "$CUSTOMER_ID"
	setenv CONFIG "$CONFIG"
    setenv iMC_PASS "$iMC"
    setenv EX_CARD_1 "$ExCard1"
    setenv EX_CARD_2 "$ExCard2"
    setenv EX_CARD_3 "$ExCard3"

}
