# Pro Max TV

Client Flutter pour serveurs Xtream Codes : Live, Films, Séries.
Lecteur vide : l'utilisateur saisit ses propres accès. Aucun serveur ni identifiant n'est embarqué.

## Lancer en local
```bash
flutter create --platforms=android,ios --org com.promaxtv --project-name promax_tv .
flutter pub get
flutter run
```
Android : ajouter `android.permission.INTERNET` et `android:usesCleartextTraffic="true"` dans `AndroidManifest.xml` si le serveur est en HTTP.

## Build automatique
Chaque push sur `main` lance GitHub Actions et produit l'APK (onglet Actions > Artifacts).
