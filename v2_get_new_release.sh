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
ARTISTS_SHORT=$(echo "$TOP_ARTISTS_SHORT" | jq -s '{items: ([.[].items] | add)}')
ARTISTS_MEDIUM=$(echo "$TOP_ARTISTS_MEDIUM" | jq -s '{items: ([.[].items] | add)}')
ARTISTS_LONG=$(echo "$TOP_ARTISTS_LONG" | jq -s '{items: ([.[].items] | add)}')

TOP_TRACKS_SHORT=$(curl -s --request GET --url 'https://api.spotify.com/v1/me/top/tracks?time_range=short_term&limit=50' --header "Authorization: Bearer $ACCESS_TOKEN")
TOP_TRACKS_MEDIUM=$(curl -s --request GET --url 'https://api.spotify.com/v1/me/top/tracks?time_range=medium_term&limit=50' --header "Authorization: Bearer $ACCESS_TOKEN")
TOP_TRACKS_LONG=$(curl -s --request GET --url 'https://api.spotify.com/v1/me/top/tracks?time_range=long_term&limit=50' --header "Authorization: Bearer $ACCESS_TOKEN")

# (nettoyage) suppression des affichages non nécessaires au scoring

# Attribution d'une note aux NEW_RELEASE selon présence des artistes/genres dans les tops
# Construire les ensembles d'IDs d'artistes par période
SHORT_IDS_JSON=$(echo "$ARTISTS_SHORT" | jq '[.items[].id]')
MEDIUM_IDS_JSON=$(echo "$ARTISTS_MEDIUM" | jq '[.items[].id]')
LONG_IDS_JSON=$(echo "$ARTISTS_LONG" | jq '[.items[].id]')

# Construire les ensembles de genres par période (dérivés des artistes)
SHORT_GENRES_JSON=$(echo "$ARTISTS_SHORT" | jq '[.items[].genres[]?] | unique')
MEDIUM_GENRES_JSON=$(echo "$ARTISTS_MEDIUM" | jq '[.items[].genres[]?] | unique')
LONG_GENRES_JSON=$(echo "$ARTISTS_LONG" | jq '[.items[].genres[]?] | unique')

# Construire une map artisteId -> genres (union des périodes)
ALL_ARTISTS_UNION=$(echo "$ARTISTS_SHORT $ARTISTS_MEDIUM $ARTISTS_LONG" | jq -s '[.[].items[]] | sort_by(.id) | unique_by(.id)')
ARTIST_MAP_JSON=$(echo "$ALL_ARTISTS_UNION" | jq 'map({key: .id, value: (.genres // [])}) | from_entries')

# Compléter la map avec les artistes de NEW_RELEASE non connus (pour récupérer leurs genres)
NEW_RELEASE_ARTIST_IDS=$(echo "$NEW_RELEASE" | jq -r '.albums.items[].artists[].id' | sort -u)
KNOWN_ARTIST_IDS=$(echo "$ARTIST_MAP_JSON" | jq -r 'keys[]' | sort -u)
MISSING_ARTIST_IDS=$(comm -23 <(echo "$NEW_RELEASE_ARTIST_IDS") <(echo "$KNOWN_ARTIST_IDS"))

if [ -n "$MISSING_ARTIST_IDS" ]; then
    while IFS= read -r batch; do
        batch=${batch%,}
        if [ -n "$batch" ]; then
            RESP=$(curl -s --request GET --url "https://api.spotify.com/v1/artists?ids=$batch" --header "Authorization: Bearer $ACCESS_TOKEN")
            EXTRA_MAP=$(echo "$RESP" | jq '(.artists // []) | map({key: .id, value: (.genres // [])}) | from_entries')
            ARTIST_MAP_JSON=$(printf '%s\n%s' "$ARTIST_MAP_JSON" "$EXTRA_MAP" | jq -s '.[0] * .[1]')
        fi
    done < <(echo "$MISSING_ARTIST_IDS" | awk 'NR%50{printf $0","; next} {print $0} END{if(NR%50)print ""}')
fi

# (nettoyage) suppression des affichages des genres par période et par album

# Construire l'ensemble des albums provenant de mes tracks favoris (IDs)
FAV_ALBUM_IDS_JSON=$(echo "$TOP_TRACKS_SHORT $TOP_TRACKS_MEDIUM $TOP_TRACKS_LONG" | jq -s '[.[].items[]?.album.id] | unique')

# Calculer les jours depuis la sortie pour chaque album (fraîcheur)
NOW_EPOCH=$(date +%s)
RELEASE_DAYS_MAP_JSON='{}'
while IFS=$'\t' read -r ALB_ID ALB_DATE ALB_PREC; do
    [ -z "$ALB_ID" ] && continue
    NORM_DATE="$ALB_DATE"
    if [ "$ALB_PREC" = "year" ]; then
        NORM_DATE="$ALB_DATE-01-01"
    elif [ "$ALB_PREC" = "month" ]; then
        NORM_DATE="$ALB_DATE-01"
    fi
    ALB_EPOCH=$(date -d "$NORM_DATE" +%s 2>/dev/null || echo "")
    if [ -n "$ALB_EPOCH" ]; then
        DAYS=$(( (NOW_EPOCH - ALB_EPOCH) / 86400 ))
        [ $DAYS -lt 0 ] && DAYS=0
        RELEASE_DAYS_MAP_JSON=$(printf '%s' "$RELEASE_DAYS_MAP_JSON" | jq --arg id "$ALB_ID" --argjson d $DAYS '. + {($id): $d}')
    fi
done < <(echo "$NEW_RELEASE" | jq -r '.albums.items[] | [.id, .release_date, .release_date_precision] | @tsv')

# Récupérer la popularité des albums NEW_RELEASE (full albums, batch de 20)
ALBUM_IDS=$(echo "$NEW_RELEASE" | jq -r '.albums.items[].id' | sort -u)
ALBUM_POP_MAP_JSON='{}'
if [ -n "$ALBUM_IDS" ]; then
    while IFS= read -r batch; do
        batch=${batch%,}
        if [ -n "$batch" ]; then
            RESP=$(curl -s --request GET --url "https://api.spotify.com/v1/albums?ids=$batch" --header "Authorization: Bearer $ACCESS_TOKEN")
            EXTRA_MAP=$(echo "$RESP" | jq '(.albums // []) | map({key: .id, value: (.popularity // 0)}) | from_entries')
            ALBUM_POP_MAP_JSON=$(printf '%s\n%s' "$ALBUM_POP_MAP_JSON" "$EXTRA_MAP" | jq -s '.[0] * .[1]')
        fi
    done < <(echo "$ALBUM_IDS" | awk 'NR%20{printf $0","; next} {print $0} END{if(NR%20)print ""}')
fi

# Calculer les scores des albums de NEW_RELEASE
SCORED_NEW_RELEASES=$(echo "$NEW_RELEASE" | jq \
  --argjson short "$SHORT_IDS_JSON" \
  --argjson medium "$MEDIUM_IDS_JSON" \
  --argjson long "$LONG_IDS_JSON" \
  --argjson shortGenres "$SHORT_GENRES_JSON" \
  --argjson mediumGenres "$MEDIUM_GENRES_JSON" \
  --argjson longGenres "$LONG_GENRES_JSON" \
  --argjson artistMap "$ARTIST_MAP_JSON" \
  --argjson albumPopMap "$ALBUM_POP_MAP_JSON" \
  --argjson releaseDaysMap "$RELEASE_DAYS_MAP_JSON" \
  --argjson favAlbums "$FAV_ALBUM_IDS_JSON" \
  '
  .albums.items
  | map(
      (.artists | map({id, name})) as $arts
      | [ $arts[].id ] as $aids
      | (($short | map(select(. as $sid | $aids | index($sid))) | length) > 0) as $inShort
      | (($medium | map(select(. as $sid | $aids | index($sid))) | length) > 0) as $inMedium
      | (($long | map(select(. as $sid | $aids | index($sid))) | length) > 0) as $inLong
      | (if $inShort then 40 elif $inMedium then 25 elif $inLong then 15 else 0 end) as $artistScore
      | ([$arts[].id] | map(. as $aid | $artistMap[$aid] // []) | add | unique) as $albumGenres
      | (($albumGenres | map(
            if ($shortGenres | index(.)) then 30
            elif ($mediumGenres | index(.)) then 20
            elif ($longGenres | index(.)) then 10
            else 0 end
          ) | add) // 0) as $genreScore
      | (if ($albumGenres | length) == 0 then 5 else 0 end) as $noGenreBonus
      | ($albumPopMap[.id] // 0) as $popularity
      | ($popularity * 0.2) as $popularityScore
      | ($releaseDaysMap[.id] // 0) as $daysSinceRelease
      | (30 - $daysSinceRelease) as $freshnessScore
      | (.id) as $albumId
      | (($favAlbums | index($albumId)) != null) as $inFavAlbums
      | (if $inFavAlbums then 50 else 0 end) as $favAlbumBonus
      | ($artistScore + $genreScore + $noGenreBonus + $popularityScore + $freshnessScore + $favAlbumBonus) as $score
      | {
          name: .name,
          artists: $arts,
          artistScore: $artistScore,
          genreScore: $genreScore,
          noGenreBonus: $noGenreBonus,
          popularity: $popularity,
          popularityScore: $popularityScore,
          daysSinceRelease: $daysSinceRelease,
          freshnessScore: $freshnessScore,
          favAlbumBonus: $favAlbumBonus,
          score: $score
        }
    )
  | sort_by(.score) | reverse
  ')

RESULT_LINES=$(echo "$SCORED_NEW_RELEASES" | jq -r '.[] | select(.score > 0) | "\(.score)\t\(.name)\t-\t\([.artists[].name] | join(", "))"')
echo "$RESULT_LINES"

