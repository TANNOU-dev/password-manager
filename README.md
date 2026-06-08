# PassVault 🔐

> Gestionnaire de mots de passe sécurisé — chiffré de bout en bout

**PassVault** est une application de gestion de mots de passe avec chiffrement AES, authentification biométrique, et générateur de mots de passe forts. Développé avec **Flutter** (frontend) et **Node.js/Express + SQLite** (backend).

---

## 🖼️ Aperçu

| Connexion | Coffre-fort | Ajouter | Générateur |
|-----------|------------|---------|------------|
| Authentification sécurisée par mot de passe maître + empreinte digitale | Liste des mots de passe avec recherche et icônes par site | Formulaire avec indicateur de force et chiffrement E2E | Générateur paramétrable : longueur, maj, min, chiffres, symboles |

---

## ✨ Fonctionnalités

- **🔐 Chiffrement AES** — tous les mots de passe sont chiffrés avant stockage
- **👆 Authentification biométrique** — déverrouillage par empreinte / Face ID
- **🔑 Générateur intégré** — mots de passe forts de 4 à 64 caractères
- **📂 Export / Import** — JSON et CSV pour sauvegarder ou migrer
- **🔍 Recherche rapide** — filtre par site ou email
- **🛡️ Analyse sécurité** — détection des mots de passe faibles ou compromis
- **🌙 Thème Dark** — design moderne Deep Navy
- **📱 Multi-plateforme** — Android, iOS, Web, Linux, Windows, macOS

---

## 🏗️ Architecture

```
password-manager/
├── app/                         # Sources de base
├── app_build/                   # ✅ Application Flutter (frontend)
│   ├── lib/
│   │   ├── main.dart            # Thème, design system, entrée
│   │   ├── screens/
│   │   │   ├── login_screen.dart       # Écran de connexion
│   │   │   ├── setup_screen.dart       # Création du coffre-fort
│   │   │   ├── home_screen.dart        # Coffre-fort principal
│   │   │   ├── add_password_screen.dart # Ajout / modification
│   │   │   ├── generator_screen.dart   # Générateur de mots de passe
│   │   │   └── settings_screen.dart    # Paramètres
│   │   └── services/
│   │       └── api_service.dart        # Client API REST
│   ├── android/                  # Build Android
│   ├── ios/                      # Build iOS
│   ├── linux/                    # Build Linux Desktop
│   ├── web/                      # Build Web
│   └── pubspec.yaml
├── backend/                     # ✅ API REST Node.js
│   ├── server.js                 # Serveur Express
│   ├── database.js               # SQLite + chiffrement AES
│   └── package.json
└── build-deb.sh                 # Script build Debian/Ubuntu
```

---

## 🚀 Installation & Démarrage

### Prérequis

- **Flutter** 3.x ([installer](https://flutter.dev/docs/get-started/install))
- **Node.js** 18+ et **npm**
- **Android Studio** (pour build Android) ou **Chrome/Firefox** (pour web)

### 1. Backend

```bash
cd backend
npm install
node server.js
```

Le serveur démarre sur `http://localhost:3000`.

### 2. Application

```bash
cd app_build
flutter pub get
flutter run -d web-server --web-port=8080
```

Puis ouvrir **Firefox** (ou Chrome) → `http://localhost:8080`

> **Note :** Pour le développement web, l'URL du backend doit pointer sur `localhost:3000` (modifiable dans `lib/services/api_service.dart`).

---

## 🌐 Déploiement (VPS)

### Prérequis VPS

- Ubuntu/Debian 22.04+
- Node.js 18+, npm
- Nginx (proxy inverse)
- Un nom de domaine (optionnel)

### Backend (Node.js)

```bash
cd backend
npm install --production

# Avec PM2 pour la gestion de processus
npm install -g pm2
pm2 start server.js --name passvault-api
pm2 save
pm2 startup
```

### Frontend (Flutter Web)

```bash
cd app_build
flutter build web --release
# Les fichiers statiques sont dans build/web/
# Servir avec Nginx
```

### Configuration Nginx

```nginx
server {
    listen 80;
    server_name votre-domaine.com;

    # Frontend Flutter
    root /var/www/passvault/build/web;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    # API Proxy vers Node.js
    location /api/ {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
```

---

## 🛠️ Stack Technique

| Composant | Technologie |
|-----------|------------|
| **Frontend** | Flutter 3.41 / Dart 3.11 |
| **Backend** | Node.js, Express |
| **Base de données** | SQLite (chiffrée côté client) |
| **Chiffrement** | AES-256-CBC + PBKDF2 (10 000 itérations) |
| **Biométrie** | local_auth (Face ID / empreinte) |
| **Design** | Thème sombre Deep Navy, Inter + JetBrains Mono |

---

## 🤝 Contribution

1. Fork le projet
2. Crée une branche (`git checkout -b feature/ma-fonctionnalite`)
3. Commit les changements (`git commit -m 'feat: ajout de ma fonctionnalité'`)
4. Push (`git push origin feature/ma-fonctionnalite`)
5. Ouvre une Pull Request

---

## 📄 Licence

Projet personnel — Tannou Abou © 2026

---

## 📞 Contact

- **Développeur :** Tannou Abou — [@Tannouabou](https://t.me/Tannouabou)
- **Master :** Université Peleforo Gon Coulibaly, Korhogo (Côte d'Ivoire)
