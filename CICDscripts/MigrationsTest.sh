#!/bin/bash

 set -e

 echo "Downloading and installing spawnctl..."
 curl -sL https://run.spawn.cc/install | sh > /dev/null 2>&1
 export PATH=$HOME/.spawnctl/bin:$PATH
 echo "spawnctl successfully installed"

 export SPAWN_DB_IMAGE_NAME=apollo_flyway:stage

 echo
 echo "Creating db backup Spawn data container from image '$SPAWN_DB_IMAGE_NAME'..."
 dbContainerName=$(spawnctl create data-container --image $SPAWN_DB_IMAGE_NAME --lifetime 10m --accessToken $SPAWNCTL_ACCESS_TOKEN -q)

 databaseName="Apollo_Flyway"
 dbJson=$(spawnctl get data-container $dbContainerName -o json)
 dbHost=$(echo $dbJson | jq -r '.host')
 dbPort=$(echo $dbJson | jq -r '.port')
 dbUser=$(echo $dbJson | jq -r '.user')
 dbPassword=$(echo $dbJson | jq -r '.password')

 echo "Successfully created Spawn data container '$dbContainerName'"
 echo

 docker pull mcr.microsoft.com/mssql/server:2019-latest > /dev/null 2>&1
 docker pull flyway/flyway > /dev/null 2>&1

 echo
 echo "Starting migration of database with flyway"
 
 docker run --net=host --rm -v $PWD/sql:/flyway/sql flyway/flyway -url="jdbc:sqlserver://$dbHost:$dbPort;databaseName=$databaseName;encrypt=true;trustServerCertificate=true" -user=$dbUser -password=$dbPassword -driver=com.microsoft.sqlserver.jdbc.SQLServerDriver -X migrate

 echo "Successfully migrated 'Apollo_Flyway' database"
 echo

 spawnctl delete data-container $dbContainerName --accessToken $SPAWNCTL_ACCESS_TOKEN -q

 echo "Successfully cleaned up the Spawn data container '$dbContainerName'"