# BD VR

Lecteur de bandes dessinées immersif pour Meta Quest 3, construit avec Godot 4.7.2 et OpenXR.

## V1

- Bibliothèque 3D avec les couvertures de **Silo**, **Arthéus**, **Enquête** et **Isekai**.
- Navigation Quest : joystick gauche/droite, gâchette ou A pour ouvrir, B/Menu pour revenir.
- Lecteur de planches avec ajustement automatique portrait/paysage.
- Sauvegarde locale de la progression.
- 3 planches d'aperçu légères par BD pour tester immédiatement l'ergonomie sans gonfler l'APK.
- Base `ZIPReader` prête pour l'import CBZ/ZIP lors de l'étape suivante.
- Build APK automatique via GitHub Actions.

## Pourquoi les BD complètes ne sont pas dans l'APK

Les archives source sont volumineuses. Les intégrer au dépôt et à chaque APK rendrait les builds très lourds. La cible est donc un APK léger, puis un import des ZIP/CBZ depuis le casque.

## Build

Le workflow **Build Quest APK** produit `bd-vr.apk` en artifact GitHub Actions.

## Étapes prévues

1. V2 : import ZIP/CBZ via sélecteur de fichiers Android/Quest et cache de miniatures.
2. V3 : mode double page, zoom et repositionnement spatial.
3. V4 : bibliothèque plus immersive avec ambiances par série.
4. V5 : hand tracking et mode passthrough / réalité mixte.
