#!/bin/bash
# =============================================
# build-deb.sh - Build .deb pour Password Manager
# =============================================
set -e

APP_NAME="password-manager"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT_DIR/app_build"

echo "🔧 Build Linux release..."
cd "$APP_DIR"
flutter build linux --release

echo ""
echo "📦 Création du paquet .deb..."
cd "$ROOT_DIR"

BUNDLE="$APP_DIR/build/linux/x64/release/bundle"
PKG_DIR="pkg"
DEB_FILE="${APP_NAME}-linux-amd64.deb"

# Création de la structure
mkdir -p "$PKG_DIR/DEBIAN"
mkdir -p "$PKG_DIR/usr/local/bin/$APP_NAME"
mkdir -p "$PKG_DIR/usr/share/applications"
mkdir -p "$PKG_DIR/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$PKG_DIR/usr/share/icons/hicolor/48x48/apps"
mkdir -p "$PKG_DIR/usr/share/icons/hicolor/96x96/apps"

# Copie du binaire et des librairies
cp -r "$BUNDLE"/* "$PKG_DIR/usr/local/bin/$APP_NAME/" 2>/dev/null || true
if [ -d "$BUNDLE/$APP_NAME" ]; then
    cp -r "$BUNDLE/$APP_NAME"/* "$PKG_DIR/usr/local/bin/$APP_NAME/"
fi

# Icônes
ICON_SRC="$APP_DIR/linux/my_icon.png"
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$PKG_DIR/usr/share/icons/hicolor/256x256/apps/${APP_NAME}.png"
    # Générer les petites tailles
    convert "$ICON_SRC" -resize 96x96 "$PKG_DIR/usr/share/icons/hicolor/96x96/apps/${APP_NAME}.png" 2>/dev/null || true
    convert "$ICON_SRC" -resize 48x48 "$PKG_DIR/usr/share/icons/hicolor/48x48/apps/${APP_NAME}.png" 2>/dev/null || true
fi

# Fichier de contrôle
cat > "$PKG_DIR/DEBIAN/control" << EOF
Package: $APP_NAME
Version: 1.0.0
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Tannou Abou
Description: Mes mot de passe - Gestionnaire de mots de passe
 Coffre-fort de mots de passe chiffré et synchronisé.
 Chiffrement AES-256, synchronisation via VPS.
 Compatible avec l'application Android.
EOF

# Entrée .desktop
cat > "$PKG_DIR/usr/share/applications/${APP_NAME}.desktop" << EOF
[Desktop Entry]
Name=Mes mot de passe
Comment=Gestionnaire de mots de passe sécurisé
Exec=/usr/local/bin/$APP_NAME/password_manager
Icon=$APP_NAME
Terminal=false
Type=Application
Categories=Utility;Security;
StartupNotify=true
EOF

# Post-installation : mise à jour du cache des icônes
cat > "$PKG_DIR/DEBIAN/postinst" << 'POST'
#!/bin/bash
set -e
if command -v gtk-update-icon-cache &> /dev/null; then
    gtk-update-icon-cache -f /usr/share/icons/hicolor/ 2>/dev/null || true
fi
if command -v update-desktop-database &> /dev/null; then
    update-desktop-database 2>/dev/null || true
fi
echo "✅ PassVault installé ! Cherchez-le dans le menu Applications."
POST
chmod 755 "$PKG_DIR/DEBIAN/postinst"

# Build du .deb
dpkg-deb --build "$PKG_DIR" "$DEB_FILE"

# Nettoyage
rm -rf "$PKG_DIR"

# Nettoyer le bundle de build (optionnel)
# rm -rf "$APP_DIR/build"

echo ""
echo "============================================"
echo "✅ Fichier créé : $ROOT_DIR/$DEB_FILE"
echo "   Taille : $(du -h "$DEB_FILE" | cut -f1)"
echo ""
echo "📥 Pour installer :"
echo "   sudo dpkg -i $DEB_FILE"
echo "============================================"
