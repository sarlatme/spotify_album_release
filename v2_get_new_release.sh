#!/bin/bash

CLIENT_ID="$1"
CLIENT_SECRET="$2"
REDIRECT_URI="http://127.0.0.1:8080/callback"
SCOPES="user-follow-read user-top-read user-read-recently-played"

# 1. Générer l'URL d'autorisation
AUTH_URL="https://accounts.spotify.com/authorize?response_type=code&client_id=$CLIENT_ID&scope=$(echo $SCOPES | tr ' ' '+')&redirect_uri=$REDIRECT_URI"

echo "Ouvrez cette URL dans votre navigateur :"
echo "$AUTH_URL"
echo ""
echo "Après autorisation, copiez le code depuis l'URL de redirection :"
read -p "Entrez le code d'autorisation : " AUTH_CODE

# 2. Échanger le code contre un token
AUTH_HEADER=$(echo -n "$CLIENT_ID:$CLIENT_SECRET" | base64 -w 0)
TOKEN_RESPONSE=$(curl -X POST -H "Authorization: Basic $AUTH_HEADER" -d "grant_type=authorization_code&code=$AUTH_CODE&redirect_uri=$REDIRECT_URI" https://accounts.spotify.com/api/token)

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.refresh_token')

echo "$ACCESS_TOKEN"

echo "Access Token obtenu !"

NEW_RELEASE=$(curl --request GET --url https://api.spotify.com/v1/browse/new-releases --header "Authorization: Bearer $ACCESS_TOKEN")

TOP_ARTISTS_SHORT=$(curl -s --request GET --url 'https://api.spotify.com/v1/me/top/artists?time_range=short_term&limit=50' --header "Authorization: Bearer $ACCESS_TOKEN")
TOP_ARTISTS_MEDIUM=$(curl -s --request GET --url 'https://api.spotify.com/v1/me/top/artists?time_range=medium_term&limit=50' --header "Authorization: Bearer $ACCESS_TOKEN")
TOP_ARTISTS_LONG=$(curl -s --request GET --url 'https://api.spotify.com/v1/me/top/artists?time_range=long_term&limit=50' --header "Authorization: Bearer $ACCESS_TOKEN")

TOP_TRACKS_SHORT=$(curl -s --request GET --url 'https://api.spotify.com/v1/me/top/tracks?time_range=short_term&limit=50' --header "Authorization: Bearer $ACCESS_TOKEN")
TOP_TRACKS_MEDIUM=$(curl -s --request GET --url 'https://api.spotify.com/v1/me/top/tracks?time_range=medium_term&limit=50' --header "Authorization: Bearer $ACCESS_TOKEN")
TOP_TRACKS_LONG=$(curl -s --request GET --url 'https://api.spotify.com/v1/me/top/tracks?time_range=long_term&limit=50' --header "Authorization: Bearer $ACCESS_TOKEN")

get_top_genres() {
    local artists_data="$1"
    local temp_genres_file="/tmp/spotify_genres_$$"

    echo "$artists_data" | jq -r '.items[].genres[]' | sort | uniq -c | sort -nr > "$temp_genres_file"
    local genres_list=()
    while IFS= read -r line; do
        genre=$(echo "$line" | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//')
        genres_list+=("$genre")
    done < "$temp_genres_file"

    rm -f "$temp_genres_file"

    IFS=','
    echo "${genres_list[*]}"
}

ALL_ARTISTS_DATA=$(echo "$TOP_ARTISTS_SHORT $TOP_ARTISTS_MEDIUM $TOP_ARTISTS_LONG" | jq -s '{items: ([.[].items] | add)}')
ALL_GENRES=$(get_top_genres "$ALL_ARTISTS_DATA")
echo $ALL_GENRES

# faire la meme chose pour les tracks si meme genre alors combiné
# audio feature des tracks et recommendation spotify