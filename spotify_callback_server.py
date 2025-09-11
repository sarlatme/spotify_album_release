#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
import urllib.parse

HOST = "127.0.0.1"
PORT = 8080

class SpotifyAuthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        # Découper l'URL et extraire les paramètres
        parsed_url = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed_url.query)

        if "code" in params:
            code = params["code"][0]
            print(f"\n>>> Code reçu depuis Spotify : {code}\n")

            # Réponse au navigateur
            self.send_response(200)
            self.send_header("Content-type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write("<h1>Autorisation réussie ✅</h1>".encode("utf-8"))
            self.wfile.write("<p>Retournez dans votre terminal, le code a été récupéré.</p>".encode("utf-8"))
        else:
            self.send_response(400)
            self.send_header("Content-type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write("<h1>Erreur ❌</h1><p>Pas de code trouvé dans l'URL.</p>".encode("utf-8"))

def run():
    server = HTTPServer((HOST, PORT), SpotifyAuthHandler)
    print(f"Serveur en écoute sur http://{HOST}:{PORT}/callback ...")
    print("Ouvrez l'URL d'autorisation Spotify dans votre navigateur.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    server.server_close()
    print("Serveur arrêté.")

if __name__ == "__main__":
    run()
