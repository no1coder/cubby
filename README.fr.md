<p align="center">
  <img src="docs/assets/icon.png" width="128" height="128" alt="Icône de l’app Cubby">
</p>

<h1 align="center">Cubby</h1>

<p align="center">
  <b>Tout ce que vous copiez, à une touche de distance.</b><br>
  Un gestionnaire de presse-papiers natif pour macOS, pensé pour le clavier, qui ne quitte jamais votre Mac.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="Licence : MIT"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.zh-Hant.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.es.md">Español</a> · <a href="README.de.md">Deutsch</a> · <b>Français</b>
</p>

```sh
brew install --cask no1coder/tap/cubby
```

Ou téléchargez le DMG notarisé depuis les [Releases](https://github.com/no1coder/cubby/releases/latest). Nécessite macOS 14 ou ultérieur, sur Mac Apple silicon ou Intel.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/screenshots/panel-dark.png">
    <source media="(prefers-color-scheme: light)" srcset="docs/assets/screenshots/panel-light.png">
    <img src="docs/assets/screenshots/panel-light.png" width="380" alt="Le panneau Cubby affichant des cartes de texte, de lien, de code, de couleur, de fichier et d’image">
  </picture>
</p>

Cubby se loge dans la barre des menus et retient tout ce que vous copiez : texte, liens, code, couleurs, images et fichiers. Appuyez sur <kbd>⇧⌘V</kbd>, tapez quelques lettres puis <kbd>↩</kbd> pour coller dans l’app que vous utilisiez, sans toucher à la souris. Cubby s’adresse à ceux qui copient-collent toute la journée (développeurs, designers, rédacteurs, et tous ceux qui jonglent avec des adresses et des extraits de texte) et veulent un outil rapide qui respecte leur vie privée. Votre historique reste sur votre Mac ; Cubby ne se connecte à Internet que pour vérifier la présence d’une nouvelle version (une fois par jour, désactivable) ou pour traduire avec un modèle de langage que vous avez vous-même configuré.

**Points forts**

- **Recherche et collage instantanés.** Des cartes adaptées aux liens, au code, aux couleurs et aux fichiers, une recherche qui lit aussi le texte des images, et un collage avec <kbd>↩</kbd> ou <kbd>⌘1</kbd>–<kbd>⌘9</kbd>.
- **Votre disposition.** Un panneau flottant, une barre latérale ancrée au bord droit ou une étagère de cartes en bas de l’écran ; plus une grille réservée aux images sur <kbd>⌃⇧V</kbd>.
- **Captures d’écran et annotations.** <kbd>⇧⌘2</kbd> capture une fenêtre ou une zone, vous laisse l’annoter et la range dans votre historique.
- **La corde à linge.** Suspendez jusqu’à 12 images en haut de l’écran et faites-les descendre depuis la barre des menus dès que vous en avez besoin.
- **Protection des adresses.** Soyez averti lorsqu’un logiciel malveillant remplace une adresse crypto ou un numéro de carte que vous avez copié.
- **Traduction sous macOS 26.** Traduisez sur place les éléments du presse-papiers et les captures d’écran, sur l’appareil ou avec votre propre modèle.

## Démonstration

<table>
  <tr>
    <td align="center" width="50%">
      <img src="docs/assets/gifs/search-paste.gif" alt="Ouverture du panneau Cubby avec Maj-Commande-V, saisie de quelques lettres pour filtrer l’historique, puis Retour pour coller le résultat dans une autre app"><br>
      <sub><b>Rechercher et coller.</b> Tapez pour trouver, <kbd>↩</kbd> pour coller.</sub>
    </td>
    <td align="center" width="50%">
      <img src="docs/assets/gifs/clothesline.gif" alt="Glissement vers le bas depuis la barre des menus pour faire descendre une corde à linge d’images, survol des photos, puis clic sur l’une d’elles pour l’annoter"><br>
      <sub><b>Corde à linge.</b> Glissez vers le bas depuis la barre des menus pour retrouver vos images épinglées.</sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="50%">
      <img src="docs/assets/gifs/screenshot-annotate.gif" alt="Capture avec Maj-Commande-2, sélection d’une zone, ajout d’un cadre, d’un texte et d’une flèche, puis copie"><br>
      <sub><b>Capture et annotations.</b> Capturez, annotez, collez.</sub>
    </td>
    <td align="center" width="50%">
      <img src="docs/assets/gifs/address-guard.gif" alt="Une adresse Ethereum copiée est remplacée dans le presse-papiers et Cubby affiche un avertissement comparant les deux adresses caractère par caractère, différences en rouge"><br>
      <sub><b>Protection des adresses.</b> Une adresse substituée est repérée avant que vous ne la colliez.</sub>
    </td>
  </tr>
  <tr>
    <td align="center" colspan="2">
      <img src="docs/assets/gifs/screenshot-translate.gif" width="640" alt="Deux fenêtres en anglais d’une capture traduites en chinois sur place, ligne par ligne, puis comparées à l’original avec un séparateur"><br>
      <sub><b>Traduction des captures (macOS 26).</b> Appuyez sur <kbd>⇧⌘T</kbd> : le texte est remplacé sur place, mise en page intacte ; faites glisser le séparateur pour comparer.</sub>
    </td>
  </tr>
</table>

## Fonctionnalités

**Capturer et retrouver**

- Enregistre le texte (le texte enrichi conserve sa mise en forme RTF / HTML), les liens, les couleurs HEX, les images et les fichiers. Copier à nouveau un élément le remonte en tête. Les favoris n’expirent jamais ; le reste est limité au nombre que vous choisissez (de 50 à 2 000 éléments, 500 par défaut).
- Les cartes ressemblent à leur contenu : les liens affichent le titre de la page et l’adresse complète, le code indique son langage avec coloration syntaxique, les couleurs montrent leurs valeurs HEX et rgb(), les images apparaissent en entier. Chaque carte indique l’app source, l’heure et son numéro <kbd>⌘</kbd>, regroupées en Aujourd’hui, Hier et Plus ancien.
- Commencez simplement à taper pour chercher. Chaque mot doit correspondre, les correspondances sont surlignées, les meilleures apparaissent en premier et chaque catégorie affiche son nombre de résultats. Les chemins de fichiers, les apps sources, les titres de liens et le texte des images (reconnu sur votre Mac) sont aussi consultables.
- Filtrez par Texte, Liens, Images, Fichiers, Couleurs ou Favoris avec <kbd>⇥</kbd>. <kbd>Espace</kbd> ouvre un aperçu latéral ; <kbd>⌘B</kbd> (**Pick Words**, choisir des mots) découpe un texte en pastilles de mots pour ne coller que la partie utile.
- Cinq positions du panneau : près du pointeur, sous l’icône de la barre des menus, au centre, ancré au bord droit en barre latérale pleine hauteur, ou ancré en bas en étagère de cartes. <kbd>⌃⇧V</kbd> ouvre uniquement vos images dans une grille. Apparence Clair, Sombre ou Selon le système ; Liquid Glass sous macOS 26.

**Coller**

- <kbd>↩</kbd> colle dans l’app que vous utilisiez (le pied du panneau indique laquelle), <kbd>⇧↩</kbd> colle dans l’autre format (original ↔ texte brut), <kbd>⌘↩</kbd> se contente de copier.
- <kbd>⌘1</kbd> – <kbd>⌘9</kbd> collent l’un des neuf premiers éléments ; toute carte peut être glissée dans une autre app.
- Survolez une carte pour la mettre en favori, la prévisualiser, la supprimer ou l’épingler. <kbd>⌘⌫</kbd> supprime, <kbd>⌘Z</kbd> la restaure.

**Captures d’écran**

- <kbd>⇧⌘2</kbd> fige l’écran : survolez pour choisir une fenêtre (<kbd>⇥</kbd> ou le défilement parcourt les fenêtres superposées), tracez une zone, ou appuyez sur <kbd>Espace</kbd> pour capturer proprement une seule fenêtre avec son ombre.
- Annotez avec rectangles, ellipses, flèches, stylo, surligneur, mosaïque, texte et étapes numérotées, tous modifiables jusqu’à la validation.
- Le résultat est copié **et enregistré dans votre historique**. Vous pouvez aussi l’épingler à l’écran, l’enregistrer en PNG ou en extraire le texte par OCR sur l’appareil. Une loupe copie la couleur sous le pointeur avec <kbd>C</kbd>.

**Corde à linge**

- Appuyez sur <kbd>⌘L</kbd> sur une image pour la suspendre à une corde en haut de l’écran (jusqu’à 12). Pour la faire descendre, glissez vers le bas depuis un endroit vide de la barre des menus, laissez le pointeur sur le bord supérieur, appuyez sur <kbd>⌃⌥T</kbd> ou passez par le menu.
- Double-cliquez sur une photo pour la copier, glissez-la dans une app ou cliquez dessus pour l’agrandir et l’annoter ; **Done & Hang Back** (terminer et raccrocher) enregistre le résultat comme nouvel élément et conserve l’original. Les photos sur la corde échappent au nettoyage de l’historique.

**Protection des adresses**

- Si une adresse Bitcoin, Ethereum / EVM, TRON, Solana ou Litecoin, ou un numéro de carte bancaire, que vous avez copié est remplacé dans le presse-papiers dans les secondes qui suivent alors que la même app reste au premier plan, un avertissement compare les deux valeurs caractère par caractère, différences en rouge. **Restore What I Copied** (restaurer ce que j’ai copié) remet votre valeur en place.
- L’élément de remplacement est marqué en rouge dans l’historique et ne peut être ni collé, ni copié, ni glissé. Quand vous collez une adresse depuis Cubby, celui-ci vérifie d’abord que le presse-papiers correspond toujours.
- Cubby ne vide jamais votre presse-papiers et n’intercepte jamais <kbd>⌘V</kbd>. Réglages dans **Settings › Security** (Sécurité).

**Traduction** (macOS 26)

- <kbd>⌘T</kbd> traduit l’élément sélectionné dans une carte à côté du panneau ; <kbd>⌥↩</kbd> traduit et colle en une seule étape ; maintenez <kbd>⌥</kbd> pour prévisualiser une traduction dans la liste.
- <kbd>⇧⌘T</kbd> dans une capture d’écran traduit son texte sur place, bloc par bloc.
- Utilise par défaut la traduction sur l’appareil d’Apple, ou tout modèle compatible OpenAI que vous configurez (DeepSeek, Qwen, Kimi, Zhipu GLM, OpenAI, OpenRouter, un Ollama local ou une URL personnalisée). Voir [Traduction](#traduction).

**Confidentialité et finitions**

- Tout reste en local, exclu de Time Machine, sans statistiques ni télémétrie. Ignore le contenu des gestionnaires de mots de passe, les apps que vous excluez et le texte qui ressemble à une clé d’API, une clé privée ou un JWT. Mettez l’enregistrement en pause à tout moment. Voir [Confidentialité](#confidentialité).
- Swift 6 avec SwiftUI et AppKit, aucune dépendance tierce, binaire universel. Uniquement dans la barre des menus, sans icône dans le Dock. Interface en anglais et en chinois simplifié. Compatible avec VoiceOver, Réduire les animations et Augmenter le contraste.
- Un petit point bleu sur l’icône de la barre des menus vous signale la sortie d’une nouvelle version.

## Design

L’interface de la v0.3 a d’abord été conçue sous forme de maquettes. Elles sont présentées ici avec l’interface chinoise, et certains détails ont changé pendant le développement ; le [guide d’utilisation](docs/USER-GUIDE.md) décrit l’app telle qu’elle est livrée. Toutes les maquettes se trouvent dans [docs/design/ui-upgrade](docs/design/ui-upgrade).

<table>
  <tr>
    <td align="center" width="33%">
      <picture>
        <source media="(prefers-color-scheme: light)" srcset="docs/design/ui-upgrade/MainLight.png">
        <img src="docs/design/ui-upgrade/Main.png" width="280" alt="Maquette du panneau flottant : champ de recherche, barre de catégories, cartes typées pour une note, un lien GitHub, du code Swift, une couleur et une image, avec un menu contextuel">
      </picture><br>
      <sub>Panneau flottant avec cartes typées</sub>
    </td>
    <td align="center" width="33%">
      <img src="docs/design/ui-upgrade/Search.png" width="280" alt="Maquette de la recherche : correspondances surlignées avec le nombre de résultats par catégorie, un état sans résultat proposant de chercher seulement le premier mot, et l’état d’historique vide"><br>
      <sub>Recherche, aucun résultat et états vides</sub>
    </td>
    <td align="center" width="33%">
      <picture>
        <source media="(prefers-color-scheme: light)" srcset="docs/design/ui-upgrade/ImageGridLight.png">
        <img src="docs/design/ui-upgrade/ImageGrid.png" width="280" alt="Maquette de la vue Images uniquement : une grille de captures d’écran et de photos sur deux colonnes avec une barre d’outils au survol">
      </picture><br>
      <sub>Images uniquement (<kbd>⌃⇧V</kbd>)</sub>
    </td>
  </tr>
</table>

<table>
  <tr>
    <td align="center" width="50%">
      <picture>
        <source media="(prefers-color-scheme: light)" srcset="docs/design/ui-upgrade/DockRightLight.png">
        <img src="docs/design/ui-upgrade/DockRight.png" width="420" alt="Maquette du panneau ancré au bord droit en barre latérale pleine hauteur, à côté d’une fenêtre Notes">
      </picture><br>
      <sub>Ancré au bord droit</sub>
    </td>
    <td align="center" width="50%">
      <picture>
        <source media="(prefers-color-scheme: light)" srcset="docs/design/ui-upgrade/DockBottomLight.png">
        <img src="docs/design/ui-upgrade/DockBottom.png" width="420" alt="Maquette du panneau ancré en bas en étagère de cartes, avec l’aperçu ouvert au-dessus de la carte image sélectionnée">
      </picture><br>
      <sub>Ancré au bord inférieur</sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="50%">
      <picture>
        <source media="(prefers-color-scheme: light)" srcset="docs/design/ui-upgrade/ClotheslineLight.png">
        <img src="docs/design/ui-upgrade/Clothesline.png" width="420" alt="Maquette de la corde à linge : quatre photos accrochées à une corde en haut de l’écran, avec l’indication cliquer pour modifier, double-cliquer pour copier, glisser vers une app">
      </picture><br>
      <sub>La corde à linge</sub>
    </td>
    <td align="center" width="50%">
      <img src="docs/design/ui-upgrade/ClotheslineEdit.png" width="420" alt="Maquette d’une photo de la corde à linge agrandie et annotée avec un cadre, une flèche, des étapes numérotées, du texte et une mosaïque, avec les boutons Copier et Terminer et raccrocher"><br>
      <sub>Annotation d’une photo de la corde</sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="50%">
      <img src="docs/design/ui-upgrade/TamperAlert.png" width="420" alt="Maquette de l’avertissement de protection des adresses : l’adresse Ethereum copiée et celle qui l’a remplacée comparées caractère par caractère, différences en rouge"><br>
      <sub>Avertissement de protection des adresses</sub>
    </td>
    <td align="center" width="50%">
      <img src="docs/design/ui-upgrade/Preview.png" width="420" alt="Maquette de l’aperçu latéral à côté du panneau : une note en texte enrichi affichée en entier avec les boutons Traduire, Coller en texte brut et Coller"><br>
      <sub>Aperçu latéral (Espace)</sub>
    </td>
  </tr>
</table>

<table>
  <tr>
    <td align="center" width="33%">
      <img src="docs/design/ui-upgrade/Onboarding.png" width="280" alt="Maquette de l’étape 3 du guide de bienvenue : choisir un panneau flottant, une barre latérale à droite ou une étagère en bas, ainsi que l’apparence"><br>
      <sub>Guide de bienvenue en quatre étapes</sub>
    </td>
    <td align="center" width="33%">
      <picture>
        <source media="(prefers-color-scheme: light)" srcset="docs/design/ui-upgrade/SettingsLight.png">
        <img src="docs/design/ui-upgrade/Settings.png" width="280" alt="Maquette des Réglages avec barre latérale, affichant Général : apparence, raccourcis, cinq positions du panneau et options de la corde à linge">
      </picture><br>
      <sub>Réglages avec barre latérale</sub>
    </td>
    <td align="center" width="33%">
      <img src="docs/design/ui-upgrade/MenuBar.png" width="280" alt="Maquette du menu de la barre des menus : ligne d’état, ouvrir le presse-papiers, images uniquement, capture d’écran, corde à linge et sous-menu Position du panneau"><br>
      <sub>Menu de la barre des menus</sub>
    </td>
  </tr>
</table>

## Installation

### Homebrew (recommandé)

```sh
brew install --cask no1coder/tap/cubby
```

Mettez à jour avec `brew upgrade --cask cubby`.

### Téléchargement

1. Téléchargez `Cubby-x.y.z.dmg` depuis la [dernière release](https://github.com/no1coder/cubby/releases/latest).
2. Ouvrez-le et glissez **Cubby** dans **Applications**.
3. Lancez Cubby depuis Applications (et non depuis l’image disque ou votre dossier Téléchargements).

Les releases sont signées avec un Developer ID et notarisées par Apple : macOS ne demande confirmation qu’une seule fois. Chaque release comprend aussi un `.zip` et un `SHA256SUMS.txt`.

### Compiler depuis les sources

```sh
git clone https://github.com/no1coder/cubby.git
cd cubby
make install    # builds a Universal release app, copies it to /Applications and launches it
```

Nécessite Xcode 26. Consultez [CONTRIBUTING.md](CONTRIBUTING.md) pour les options de signature : avec la signature ad hoc par défaut, macOS oublie les autorisations Accessibilité et Enregistrement de l’écran à chaque recompilation.

## Guide d’utilisation

Le [guide d’utilisation](docs/USER-GUIDE.md) présente chaque fonctionnalité pas à pas. Dans l’app, choisissez **User Guide** dans le menu de l’icône de la barre des menus (il figure aussi dans **Settings › About** et en bas de l’aide des raccourcis du panneau).

## Premier lancement et autorisations

Au premier lancement, un guide en quatre étapes (Bienvenue, Autorisations, Choisir un style, Raccourci) demande deux autorisations, vous laisse choisir la disposition et l’apparence du panneau, et définit vos raccourcis. Rouvrez-le à tout moment avec **Setup Guide…** dans le menu contextuel de l’icône de la barre des menus.

**Accès au presse-papiers sous macOS 15.4 et ultérieur.** Cliquez sur **Grant Access** dans le guide (ou dans **Settings › Privacy**) et choisissez **Autoriser le collage**. S’il ne se passe rien, copiez d’abord quelque chose puis cliquez à nouveau. La demande ne propose pas de choix « toujours autoriser » : réglez donc aussi Cubby sur **Autoriser** dans Réglages Système › Confidentialité et sécurité › Coller depuis d’autres apps (appelé Coller avant macOS 26) ; une fois que macOS a posé la question, le bouton devient **Open System Settings** et vous y emmène.

| Autorisation | Pourquoi Cubby en a besoin | Où l’accorder |
| --- | --- | --- |
| **Accès au presse-papiers** (macOS 15.4 et ultérieur) | Pour lire ce que vous copiez. Sans elle, macOS redemande sans cesse, ou rien n’est enregistré. | Cliquez sur **Grant Access** et choisissez **Autoriser le collage**, puis Réglages Système › Confidentialité et sécurité › Coller depuis d’autres apps → réglez Cubby sur **Autoriser** |
| **Accessibilité** | Pour coller en envoyant <kbd>⌘V</kbd> à l’app au premier plan. Sans elle, choisir un élément ne fait que le copier. | Réglages Système › Confidentialité et sécurité › Accessibilité → activez **Cubby** |
| **Enregistrement de l’écran** (uniquement pour les captures) | Pour capturer l’écran lorsque vous prenez une capture. Jamais utilisé au lancement ni en arrière-plan. Cubby le demande à la première capture. | Réglages Système › Confidentialité et sécurité › Enregistrement de l’écran et de l’audio du système (Enregistrement de l’écran sous macOS 14) → activez **Cubby** |
| **Surveillance de l’entrée** (facultatif) | Aide la protection des adresses à distinguer vos propres <kbd>⌘C</kbd> / <kbd>⌘X</kbd> d’un remplacement. Elle ne repère que ces deux raccourcis, jamais ce que vous tapez. | **Settings › Security** › **Grant Access**, ou Réglages Système › Confidentialité et sécurité › Surveillance de l’entrée |

Après avoir activé l’Enregistrement de l’écran, macOS peut vous demander de quitter puis de rouvrir Cubby ; le bouton **Quit & Reopen Cubby** de la fenêtre Enregistrement de l’écran de Cubby fait les deux.

Cliquez sur l’icône de la barre des menus pour ouvrir le panneau. Faites un clic droit (ou Contrôle-clic) pour accéder à l’état, Only Images, Take Screenshot, Show Clothesline, Panel Position, Appearance, Pause Recording, Clear History, User Guide, Setup Guide, Check for Updates, Settings et Quit.

## Raccourcis clavier

| Touche | Action |
| --- | --- |
| <kbd>⇧⌘V</kbd> | Ouvrir ou fermer le panneau (global, personnalisable) |
| <kbd>⌃⇧V</kbd> | Ouvrir le panneau sur vos images uniquement (global, personnalisable ou désactivable) |
| <kbd>⌃⌥T</kbd> | Afficher ou masquer la corde à linge (global, personnalisable ou désactivable) |
| <kbd>⇧⌘2</kbd> | Prendre une capture d’écran (global, personnalisable ou désactivable) |
| Saisie de texte | Rechercher |
| <kbd>↑</kbd> <kbd>↓</kbd> (<kbd>←</kbd> <kbd>→</kbd> dans la grille d’images et l’étagère du bas) | Déplacer la sélection |
| <kbd>↩</kbd> ou double-clic | Coller dans l’app en cours |
| <kbd>⇧↩</kbd> / <kbd>⌘↩</kbd> | Coller dans l’autre format / copier seulement |
| <kbd>⌘1</kbd> – <kbd>⌘9</kbd> | Coller l’élément 1 à 9 |
| <kbd>Espace</kbd> / <kbd>⌘Y</kbd> | Afficher ou masquer l’aperçu (<kbd>Espace</kbd> seulement si le champ de recherche est vide) |
| <kbd>⇥</kbd> / <kbd>⇧⇥</kbd> | Catégorie suivante / précédente |
| <kbd>⌘B</kbd> | Pick Words (choisir des mots) |
| <kbd>⌘P</kbd> | Ajouter aux / retirer des favoris |
| <kbd>⇧⌘P</kbd> | Épingler l’image sélectionnée à l’écran |
| <kbd>⌘L</kbd> | Suspendre l’image sélectionnée à la corde à linge, ou l’en retirer |
| <kbd>⌘T</kbd> / <kbd>⌥↩</kbd> / maintenir <kbd>⌥</kbd> | Traduire / traduire et coller / prévisualiser la traduction (macOS 26) |
| <kbd>⌘⌫</kbd> / <kbd>⌘Z</kbd> | Supprimer / annuler la suppression |
| <kbd>⌘O</kbd> | Ouvrir le lien ou le fichier |
| <kbd>⌘,</kbd> | Réglages |
| <kbd>esc</kbd> | Revenir en arrière : fermer l’aide ou l’aperçu → effacer la recherche → fermer le panneau |

<details>
<summary><b>Raccourcis de capture d’écran</b></summary>
<br>

| Touche | Action |
| --- | --- |
| Clic / glisser | Sélectionner la fenêtre ou l’écran en surbrillance / sélectionner une zone |
| <kbd>⇥</kbd> / <kbd>⇧⇥</kbd> ou défilement | Parcourir les fenêtres superposées sous le pointeur, jusqu’à l’écran entier |
| <kbd>Espace</kbd> | Mode fenêtre : capturer seulement la fenêtre en surbrillance, sans obstruction, avec son ombre (<kbd>⌥</kbd>-clic pour omettre l’ombre) |
| Maintenir <kbd>⇧</kbd> / <kbd>⌥</kbd> / <kbd>Espace</kbd> en glissant | Sélection carrée / agrandir depuis le centre / déplacer la sélection |
| <kbd>⌘A</kbd> | Sélectionner tout l’écran |
| <kbd>↑</kbd> <kbd>↓</kbd> <kbd>←</kbd> <kbd>→</kbd> | Déplacer la sélection ou l’annotation sélectionnée de 1 pt (10 pt avec <kbd>⇧</kbd>) |
| <kbd>R</kbd> <kbd>O</kbd> <kbd>A</kbd> <kbd>P</kbd> <kbd>H</kbd> <kbd>M</kbd> <kbd>T</kbd> <kbd>N</kbd> | Rectangle, ellipse, flèche, stylo, surligneur, mosaïque, texte, numéro (la même touche ou <kbd>V</kbd> revient au pointeur) |
| <kbd>⌫</kbd> | Supprimer l’annotation sélectionnée |
| <kbd>⌘Z</kbd> / <kbd>⇧⌘Z</kbd> | Annuler / rétablir les annotations |
| <kbd>C</kbd> | Copier la couleur sous la loupe (maintenir <kbd>⇧</kbd> pour RGB) |
| <kbd>↩</kbd>, <kbd>⌘C</kbd> ou double-clic | Terminer : copier dans le presse-papiers et l’historique |
| <kbd>⌘S</kbd> | Enregistrer en PNG |
| <kbd>⌘P</kbd> | Épingler à l’écran |
| <kbd>⌘T</kbd> | Extraire le texte et le copier |
| <kbd>⇧⌘T</kbd> | Traduire le texte de la sélection (macOS 26) |
| Clic droit | Effacer la sélection et resélectionner ; sans sélection, annuler |
| <kbd>esc</kbd> | Annuler (deux fois si vous avez déjà dessiné quelque chose) |

</details>

Le bouton clavier du pied du panneau affiche la liste des raccourcis dans l’app, et un clic droit sur une carte liste ses actions. Le [guide d’utilisation](docs/USER-GUIDE.md#shortcut-reference) contient la référence complète, y compris la corde à linge, la carte de traduction et les images épinglées.

## Traduction

Sous macOS 26, sélectionnez un élément dans le panneau et appuyez sur <kbd>⌘T</kbd> : une carte de traduction s’ouvre à côté du panneau et se remplit paragraphe par paragraphe, en conservant titres, listes, gras et liens. Dans une capture d’écran, <kbd>⇧⌘T</kbd> affiche chaque traduction à l’emplacement du texte d’origine ; maintenez <kbd>Espace</kbd> pour jeter un œil à l’original ou faites glisser le séparateur pour comparer.

| Traduire une capture d’écran sur place | Traduire un élément du presse-papiers |
| :---: | :---: |
| <img src="docs/assets/screenshots/screenshot-translate-dark.png" alt="Capture de deux fenêtres en anglais dont chaque libellé et chaque ligne sont remplacés sur place par leur traduction chinoise"> | <img src="docs/assets/screenshots/clipboard-translate-dark.png" alt="La carte de traduction à côté du panneau, montrant un e-mail en anglais et sa traduction chinoise paragraphe par paragraphe"> |

Choisissez le moteur dans **Settings › Translation** (Traduction) :

- **System Translation** (par défaut) : la traduction intégrée d’Apple, sur votre Mac et hors ligne. macOS demande votre accord avant de télécharger un pack de langue.
- **Large language model** (grand modèle de langage) : tout service Chat Completions compatible OpenAI. Préréglages pour DeepSeek, Qwen (Alibaba Cloud Model Studio), Kimi (Moonshot AI), Zhipu GLM (et Z.ai), OpenAI, OpenRouter et Ollama sur votre Mac, ou une URL de base personnalisée.

Votre clé d’API est stockée dans le trousseau de session macOS, jamais dans les préférences, l’historique ou les journaux. Avec un modèle, seul le texte que vous traduisez est envoyé (pour une image ou une capture, le texte qui y a été reconnu) ; l’image elle-même n’est jamais téléversée, le texte sous une mosaïque n’est jamais envoyé, et le texte qui ressemble à un secret n’est envoyé qu’après votre confirmation (jamais depuis une image). Les services distants doivent utiliser HTTPS ; le HTTP simple n’est autorisé que pour `localhost`.

## Confidentialité

- **Tout en local.** L’historique se trouve dans `~/Library/Application Support/Cubby` : le dossier n’est lisible que par vous (0700), les fichiers sont en 0600, et il est exclu de Time Machine.
- **Contenu sensible ignoré.** Les éléments marqués comme masqués ou transitoires (comme le font les gestionnaires de mots de passe), les apps de votre liste d’apps ignorées (**Settings › Privacy**) et, sauf si vous le désactivez, le texte qui ressemble à une clé d’API, une clé privée ou un JWT.
- **Colle là où vous l’attendez.** Avant d’envoyer <kbd>⌘V</kbd>, Cubby vérifie que l’app cible est toujours au premier plan, et qu’une adresse sur le point d’être collée est toujours celle de votre presse-papiers.
- **La protection des adresses reste locale.** Avec la Surveillance de l’entrée, elle ne repère que <kbd>⌘C</kbd> et <kbd>⌘X</kbd>, jamais ce que vous tapez, et son journal de sécurité reste sur votre Mac avec des valeurs abrégées uniquement.
- **Captures d’écran et texte des images restent sur votre Mac.** L’écran n’est capturé que lorsque vous prenez une capture, et une annulation ne laisse aucune trace. Le texte des images est reconnu sur votre Mac grâce au framework Vision d’Apple et conservé uniquement dans votre fichier d’historique.
- **En ligne uniquement pour les mises à jour et le service de traduction que vous configurez.** La vérification des mises à jour (une fois par jour, activée par défaut, désactivable dans **Settings › General**) se contente de lire le dernier numéro de version sur `api.github.com/repos/no1coder/cubby/releases/latest` et n’envoie rien. Un modèle de langage que vous configurez ne reçoit que le texte que vous traduisez.
- **Aucune statistique, aucune télémétrie, aucun rapport de plantage.**

Tous les détails dans [PRIVACY.md](PRIVACY.md).

## FAQ

<details>
<summary><b>L’Accessibilité est activée, mais Cubby copie au lieu de coller.</b></summary>

macOS associe l’autorisation à la signature de code de l’app. Après une mise à jour, ou après l’installation d’une version signée différemment (par exemple une compilation depuis les sources puis une release), l’interrupteur peut sembler activé sans plus s’appliquer. Ouvrez Réglages Système › Confidentialité et sécurité › Accessibilité, sélectionnez **Cubby**, cliquez sur **−** pour le retirer, puis ajoutez-le à nouveau ou relancez Cubby et accordez l’accès. Vous pouvez aussi exécuter :

```sh
tccutil reset Accessibility io.github.no1coder.Cubby
```

Ouvrez ensuite Cubby et accordez de nouveau l’accès.

</details>

<details>
<summary><b>L’Enregistrement de l’écran est activé, mais Cubby le redemande à chaque capture.</b></summary>

Même cause que ci-dessus : l’autorisation est liée à la signature de code, donc après une mise à jour ou avec une version signée différemment, l’ancienne entrée peut sembler activée sans plus s’appliquer. Cubby le détecte et indique comment corriger le problème dans **Settings › Privacy**. Ouvrez Réglages Système › Confidentialité et sécurité › Enregistrement de l’écran et de l’audio du système (Enregistrement de l’écran sous macOS 14), sélectionnez **Cubby**, cliquez sur **−** pour le retirer, puis cliquez sur **+** et ajoutez Cubby à nouveau, et quittez puis rouvrez Cubby. Vous pouvez aussi exécuter :

```sh
tccutil reset ScreenCapture io.github.no1coder.Cubby
```

Prenez ensuite une capture et accordez de nouveau l’accès.

</details>

<details>
<summary><b>macOS indique que Cubby ne peut pas être ouvert ou vérifié.</b></summary>

Les releases officielles sont notarisées : vous ne devriez voir qu’une seule confirmation « téléchargé depuis Internet », rien de plus. Assurez-vous d’avoir téléchargé Cubby depuis la page Releases de ce dépôt ou de l’avoir installé avec Homebrew, et de le lancer depuis Applications. Vous pouvez vérifier la signature avec :

```sh
spctl -a -vvv /Applications/Cubby.app    # expect: source=Notarized Developer ID
```

Si la vérification échoue, supprimez l’app, téléchargez-la à nouveau et [ouvrez une issue](https://github.com/no1coder/cubby/issues/new/choose) si le problème persiste. Inutile de désactiver Gatekeeper.

</details>

<details>
<summary><b>Cubby m’a averti qu’une adresse avait été remplacée. Que faire ?</b></summary>

Le presse-papiers a changé pour une autre adresse ou un autre numéro de carte du même type juste après votre copie, alors que la même app restait au premier plan. Comparez les deux valeurs dans l’avertissement. Si vous n’êtes pas à l’origine du changement, cliquez sur **Restore What I Copied** et recherchez sur votre Mac les logiciels que vous ne reconnaissez pas ; si c’est bien vous (par exemple, vous avez rapidement copié une seconde adresse dans la même app), cliquez sur **I Changed It Myself** (je l’ai changé moi-même). Autoriser la Surveillance de l’entrée dans **Settings › Security** aide Cubby à reconnaître vos propres copies.

</details>

<details>
<summary><b>Où sont stockées mes données ?</b></summary>

- Historique : `~/Library/Application Support/Cubby` (`history.json` et un dossier `Images`)
- Préférences : `~/Library/Preferences/io.github.no1coder.Cubby.plist`
- Captures enregistrées : l’emplacement choisi dans la fenêtre d’enregistrement ou, si **Ask where to save each time** est désactivé, le dossier défini dans **Settings › Screenshots** (par défaut, le même dossier que les captures d’écran de macOS)

**Settings › History** permet d’afficher le dossier dans le Finder. Consultez [PRIVACY.md](PRIVACY.md) pour savoir exactement ce qui est stocké.

</details>

<details>
<summary><b>Puis-je exporter ou sauvegarder mon historique ?</b></summary>

Pas encore ; l’import et l’export figurent dans la [feuille de route](docs/ROADMAP.md). Le dossier de données est volontairement exclu de Time Machine, car le presse-papiers contient souvent des informations sensibles. En attendant l’export, vous pouvez quitter Cubby et copier `~/Library/Application Support/Cubby` à la main. Gardez à l’esprit que cette copie contient, non chiffré, tout ce que vous avez copié.

</details>

<details>
<summary><b>Comment désinstaller Cubby ?</b></summary>

Avec Homebrew, cette commande supprime l’app et toutes ses données :

```sh
brew uninstall --zap --cask cubby
```

Sinon, quittez Cubby et exécutez :

```sh
rm -rf /Applications/Cubby.app ~/Library/Application\ Support/Cubby
defaults delete io.github.no1coder.Cubby
tccutil reset All io.github.no1coder.Cubby
```

</details>

## Contribuer

Les rapports de bugs, les traductions et les pull requests sont les bienvenus. [CONTRIBUTING.md](CONTRIBUTING.md) couvre la compilation depuis les sources, les tests, le style de code et la signature locale. Merci de lire le [Code de conduite](CODE_OF_CONDUCT.md) et de signaler les problèmes de sécurité en privé, comme indiqué dans [SECURITY.md](SECURITY.md).

## Feuille de route

La v0.3 a apporté les dispositions ancrées, la grille d’images, la corde à linge, la protection des adresses, Pick Words et une refonte du panneau, des réglages et du guide de bienvenue. Encore prévu : nettoyage automatique selon l’ancienneté, sélection multiple et collage fusionné, file de collage, transformations de texte, modification avant collage, Coup d’œil et import / export ; pour les captures d’écran, la sélection d’éléments d’interface en maintenant <kbd>⌥</kbd> et la restauration de la dernière sélection. Voir [docs/ROADMAP.md](docs/ROADMAP.md) pour les détails et [CHANGELOG.md](CHANGELOG.md) pour les notes de version.

## Licence

[MIT](LICENSE) © 2026 no1coder
