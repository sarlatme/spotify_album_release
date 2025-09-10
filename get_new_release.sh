#!/bin/bash

# Vérifie que deux arguments sont fournis
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <CLIENT_ID> <CLIENT_SECRET>"
  exit 1
fi

# Récupération des arguments
CLIENT_ID="$1"
CLIENT_SECRET="$2"


# Encodage en base64
AUTH_HEADER=$(echo -n "$CLIENT_ID:$CLIENT_SECRET" | openssl base64 -A)

# Requête POST pour obtenir le token
RESPONSE=$(curl -X "POST" -H "Authorization: Basic $AUTH_HEADER" -d grant_type=client_credentials https://accounts.spotify.com/api/token)

# Extraction du token avec jq
ACCESS_TOKEN=$(echo "$RESPONSE" | jq -r '.access_token')

# Affichage du token
echo "Access Token: $ACCESS_TOKEN"

NEW_RELEASE=$(curl --request GET --url https://api.spotify.com/v1/browse/new-releases --header "Authorization: Bearer $ACCESS_TOKEN")

#Extraction et affichage des noms d'albums et artistes
# echo "$NEW_RELEASE" | jq -r '.albums.items[] | "\(.name) - \(.artists[0].name) - \(.artists[0].external_urls.spotify)"'

TOP_ARTIST=$(curl --request GET --url https://api.spotify.com/v1/me/top/artists --header "Authorization: Bearer $ACCESS_TOKEN")
echo "$TOP_ARTIST"