#!/bin/bash

CLIENT_ID="$1"
CLIENT_SECRET="$2"
REDIRECT_URI="http://127.0.0.1:8080/callback"
SCOPES="user-follow-read user-top-read user-read-recently-played"

# Fichier pour stocker le refresh token de façon persistante (dans le répertoire du script)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOKEN_FILE="${SPOTIFY_REFRESH_TOKEN_FILE:-$SCRIPT_DIR/.spotify_refresh_token}"

# Auth header commun
AUTH_HEADER=$(echo -n "$CLIENT_ID:$CLIENT_SECRET" | base64 -w 0)

# Obtenir ACCESS_TOKEN en utilisant un refresh token enregistré, sinon passer par le flux d'autorisation
if [ -f "$TOKEN_FILE" ] && [ -s "$TOKEN_FILE" ]; then
    REFRESH_TOKEN=$(cat "$TOKEN_FILE")
    TOKEN_RESPONSE=$(curl -s -X POST -H "Authorization: Basic $AUTH_HEADER" -d "grant_type=refresh_token&refresh_token=$REFRESH_TOKEN" https://accounts.spotify.com/api/token)
    ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
    NEW_REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.refresh_token // empty')
    if [ -n "$NEW_REFRESH_TOKEN" ] && [ "$NEW_REFRESH_TOKEN" != "null" ]; then
        echo "$NEW_REFRESH_TOKEN" > "$TOKEN_FILE"
    fi
else
    # 1. Générer l'URL d'autorisation (première exécution)
    AUTH_URL="https://accounts.spotify.com/authorize?response_type=code&client_id=$CLIENT_ID&scope=$(echo $SCOPES | tr ' ' '+')&redirect_uri=$REDIRECT_URI"
    echo "Ouvrez cette URL dans votre navigateur :"
    echo "$AUTH_URL"
    echo ""
    echo "Après autorisation, copiez le code depuis l'URL de redirection :"
    read -p "Entrez le code d'autorisation : " AUTH_CODE

    # 2. Échanger le code contre un token et sauvegarder le refresh token
    TOKEN_RESPONSE=$(curl -s -X POST -H "Authorization: Basic $AUTH_HEADER" -d "grant_type=authorization_code&code=$AUTH_CODE&redirect_uri=$REDIRECT_URI" https://accounts.spotify.com/api/token)
    ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
    REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.refresh_token')
    if [ -n "$REFRESH_TOKEN" ] && [ "$REFRESH_TOKEN" != "null" ]; then
        echo "$REFRESH_TOKEN" > "$TOKEN_FILE"
        echo "Refresh Token sauvegardé dans $TOKEN_FILE"
    fi
fi

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
    echo "Erreur: impossible d'obtenir un access token. Vérifiez vos identifiants et droits." >&2
    exit 1
fi


NEW_RELEASE=$(curl -s --request GET --url https://api.spotify.com/v1/browse/new-releases --header "Authorization: Bearer $ACCESS_TOKEN")

TOP_ARTISTS_SHORT=$(curl -s --request GET --url 'https://api.spotify.com/v1/me/top/artists?time_range=short_term&limit=50' --header "Authorization: Bearer $ACCESS_TOKEN")
TOP_ARTISTS_MEDIUM=$(curl -s --request GET --url 'https://api.spotify.com/v1/me/top/artists?time_range=medium_term&limit=50' --header "Authorization: Bearer $ACCESS_TOKEN")
TOP_ARTISTS_LONG=$(curl -s --request GET --url 'https://api.spotify.com/v1/me/top/artists?time_range=long_term&limit=50' --header "Authorization: Bearer $ACCESS_TOKEN")

TOP_TRACKS_SHORT=$(curl -s --request GET --url 'https://api.spotify.com/v1/me/top/tracks?time_range=short_term&limit=50' --header "Authorization: Bearer $ACCESS_TOKEN")
TOP_TRACKS_MEDIUM=$(curl -s --request GET --url 'https://api.spotify.com/v1/me/top/tracks?time_range=medium_term&limit=50' --header "Authorization: Bearer $ACCESS_TOKEN")
TOP_TRACKS_LONG=$(curl -s --request GET --url 'https://api.spotify.com/v1/me/top/tracks?time_range=long_term&limit=50' --header "Authorization: Bearer $ACCESS_TOKEN")

# RECOMMENDATIONS_SPOTIFY=$(curl -s --request GET --url 'https://api.spotify.com/v1/recommendations?seed_artists=4NHQUGzhtTLFvgF5SZesLK&seed_genres=classical%2Ccountry&seed_tracks=0c6xIDDpzE81m2q797ordA' --header "Authorization: Bearer $ACCESS_TOKEN")

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

ARTISTS_SHORT=$(echo "$TOP_ARTISTS_SHORT" | jq -s '{items: ([.[].items] | add)}')
ARTISTS_MEDIUM=$(echo "$TOP_ARTISTS_MEDIUM" | jq -s '{items: ([.[].items] | add)}')
ARTISTS_LONG=$(echo "$TOP_ARTISTS_LONG" | jq -s '{items: ([.[].items] | add)}')

ARTISTS_SHORT_GENRES=$(get_top_genres "$ARTISTS_SHORT")
ARTISTS_MEDIUM_GENRES=$(get_top_genres "$ARTISTS_MEDIUM")
ARTISTS_LONG_GENRES=$(get_top_genres "$ARTISTS_LONG")

echo "Genres des artistes : $ARTISTS_SHORT_GENRES"
echo "Genres des artistes : $ARTISTS_MEDIUM_GENRES"
echo "Genres des artistes : $ARTISTS_LONG_GENRES"

# Lister les albums des top tracks (uniques)
ALL_TRACKS_AlBUMS=$(echo "$TOP_TRACKS_SHORT $TOP_TRACKS_MEDIUM $TOP_TRACKS_LONG" | jq -s '{items: ([.[].items] | add)}')
echo "$ALL_TRACKS_AlBUMS" | jq -r '.items[].album.name' | sort -u
