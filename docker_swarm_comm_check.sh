#!/usr/bin/env bash

NODE_TYPE="wk"
CONTAINER=$(docker ps | grep "_exareme\." | cut -d' ' -f1)
if [[ "${CONTAINER}" = "" ]]; then
	CONTAINER=$(docker ps | grep "_exareme-master\." | cut -d' ' -f1)
	NODE_TYPE="ms"
fi

if [[ "${CONTAINER}" != "" ]]; then
	if [[ $# -eq 1 && "$(echo $1 | grep ':')" != "" ]]; then
		LOCAL_NODE_HOST=""
		if [[ "${NODE_TYPE}" = "wk" ]]; then
			LOCAL_NODE_HOST=$(docker network inspect mip-federation | grep -A5 "\"Name\": .*_exareme." | grep "IPv4Address" | awk -F'"' '{print $(NF-1)}')
		elif [[ "${NODE_TYPE}" = "ms" ]]; then
			LOCAL_NODE_HOST=$(docker network inspect mip-federation | grep -A5 "\"Name\": .*_exareme-master." | grep "IPv4Address" | awk -F'"' '{print $(NF-1)}')
		fi

		SWARM_TARGET_SERVICE_HOST=$(echo $1 | cut -d':' -f1)
		SWARM_TARGET_SERVICE_PORT=$(echo $1 | cut -d':' -f2)
		echo "Node type <${NODE_TYPE}>: Checking Docker Swarm TCP connectivity: ${LOCAL_NODE_HOST} => ${SWARM_TARGET_SERVICE_HOST}:${SWARM_TARGET_SERVICE_PORT}..."

		DOCKER="docker exec -it ${CONTAINER}"
		$DOCKER bash -c "timeout 2s bash -c \"if >/dev/tcp/${SWARM_TARGET_SERVICE_HOST}/${SWARM_TARGET_SERVICE_PORT}; then echo \\\"ok\\\"; else echo \\\"FAIL!\\\"; fi\" 2>/dev/null" 2>/dev/null
		ret=$?
		if [[ $ret -ne 0 ]]; then
			echo "FAIL!"
			result=$ret
		fi
	else
		echo "Usage: $0 <SWARM_TARGET_SERVICE_HOST>:<SWARM_TARGET_SERVICE_PORT>" >/dev/stderr
	fi
else
	echo "ERROR: Can't find the machine type nor the exareme container!" >/dev/stderr
fi
