## Étape 2 — Séparation kernel / user

**a) Quelle couche de l'OS (kernel/user) est responsable de :**

1. **Communiquer avec le matériel**

   => kernel. Seul le noyau s'exécute en mode privilégié et peut accéder directement aux périphériques (registres, interruptions, DMA) via ses pilotes (drivers). L'espace utilisateur passe obligatoirement par des appels système.

2. **Fournir un système de fichiers**

   => kernel. Le noyau gère l'organisation des fichiers sur le support de stockage (VFS, pilotes de FS). Les programmes utilisateur y accèdent via des appels système (`open`, `read`, `write`, `close`).

3. **Afficher une interface graphique**

   => user. L'interface graphique (serveur d'affichage, gestionnaire de fenêtres, applications) tourne en espace utilisateur. Le noyau fournit uniquement l'accès bas niveau à la carte graphique (pilote, framebuffer).

4. **Gérer le temps d'exécution des programmes en cours d'exécution sur le processeur**

   => kernel. C'est le rôle de l'ordonnanceur (scheduler) du noyau, qui décide quel processus s'exécute et quand. La préemption est déclenchée par l'interruption du timer.

**b) Explorer l'arborescence du laboratoire : quels dossiers de la racine contiennent les fichiers relatifs aux couches kernel/user ?**

Le code de SO3 se trouve dans le dossier `so3/` à la racine du dépôt :

- `so3/so3/` => espace kernel : code du noyau (`kernel/` pour le cœur, `arch/` pour le support processeur, `devices/` pour les pilotes, `mm/` pour la gestion mémoire, `fs/` pour les systèmes de fichiers, `ipc/`, `net/`, etc.).

- `so3/usr/` => espace user : applications utilisateur (`src/`) et bibliothèques utilisées par celles-ci (`lib/`).

**c) La libc est l'implémentation dans Linux de la librairie standard C, qui fournit fonctions, structures et autres éléments pour interagir avec l'OS (voir "Outils pratiques
sur Linux") :**

1. Chercher et donner le chemin vers le dossier contenant son implémentation dans

# Pas sûr à vérif

SO3 utilise **musl** comme libc pour les applications utilisateur (et non la glibc de Linux). Son implémentation n'est pas dans les sources du dépôt : elle est fournie précompilée avec la toolchain croisée `arm-linux-musleabihf`, installée dans l'image Docker sous `/opt/toolchains/musl/arm-linux-musleabihf/` (cf. `doc/source/getting_started.rst`). Les applications sont liées statiquement à musl.

Dans le dépôt, on trouve uniquement :
- la configuration de compilation de l'espace user avec cette toolchain : `so3/usr/arm-linux-musl.cmake` ;
- la recette permettant de reconstruire la toolchain si elle n'est pas fournie : `build/meta-toolchain/recipes-toolchain/musl/`. le répertoire du laboratoire

2. Dans quelle couche de l'OS se situe-t-elle ? Pourquoi ?
- Noyau SO3 (sources) → so3/so3/
- Image compilée → so3/images/ (.itb)
- Espace user → so3/usr/

=> user. La libc est une bibliothèque liée (statiquement, dans SO3) à chaque application utilisateur : son code fait partie de l'exécutable et s'exécute donc en mode non privilégié, dans l'espace d'adressage du processus. Elle ne peut pas accéder directement au matériel ni aux structures du noyau : elle sert d'interface entre les programmes et le noyau, en encapsulant les appels système. Par exemple, `printf()` met en forme la chaîne en espace user, puis appelle `write()`, qui déclenche l'instruction `svc` pour passer en mode noyau.

3. Qu'est-ce que cela implique lors du développement dans l'autre couche de l'OS ?


<br><br>

## explication supp

1. Deux « mondes » dans le processeur

Le processeur ARM peut tourner dans deux modes :

mode user (non privilégié) : c'est là que tournent tes programmes (sh, ls, ton hello.c). Ils n'ont pas le droit de toucher au matériel ni à la mémoire du noyau. S'ils essaient → le processeur bloque (exception).
mode kernel (privilégié) : c'est là que tourne le noyau SO3. Lui a tous les droits : écrire sur l'écran/UART, lire le disque, gérer la mémoire, etc.

Analogie : un restaurant. Les clients (programmes user) n'ont pas le droit d'aller en cuisine (matériel). Seul le personnel de cuisine (noyau) y entre.

2. Comment un programme user fait quand même des choses ?

Il doit demander au noyau via un appel système (syscall). Sur ARM, c'est l'instruction svc : elle fait passer le processeur en mode kernel, le noyau exécute la demande, puis revient en mode user avec le résultat.

Analogie : le client passe commande au serveur ; le serveur transmet en cuisine.

3. Et la libc dans tout ça ?

Faire un svc à la main, c'est pénible (mettre le numéro du syscall dans le registre r7, les arguments dans r0–r5, puis svc…). La libc est une bibliothèque de fonctions toutes faites qui cachent ce travail : printf, malloc, fopen, strlen…

Certaines fonctions n'ont même pas besoin du noyau (strlen compte juste des caractères). D'autres finissent par faire un appel système quand elles ont besoin du matériel.

Exemple avec printf("Hello %d", 42) :

Ton programme (mode user)
   │  printf("Hello %d", 42)
   ▼
libc (mode user)
   │  construit la chaîne "Hello 42"      ← pur calcul, pas besoin du noyau
   │  appelle write(1, "Hello 42", 8)
   │  → met les valeurs dans les registres, exécute svc
   ▼  ───────── passage en mode kernel ─────────
Noyau SO3 (mode kernel)
   │  sys_write() → pilote UART → affiche sur la console
   ▼  ───────── retour en mode user ─────────
libc → renvoie le résultat à ton programme

4. Donc pourquoi la libc est en user ?

Parce que c'est une bibliothèque comme une autre, collée à ton programme. Dans SO3, la liaison est statique : à la compilation, le code de printf etc. est copié directement dans ton exécutable hello.elf. Quand ton programme tourne en mode user, le code de la libc qu'il contient tourne donc aussi en mode user. Elle n'a aucun privilège particulier : elle est juste l'intermédiaire qui prépare les demandes au noyau.

Analogie : la libc, c'est le menu + le serveur. Le client (programme) choisit « un café » (printf) sans savoir comment la cuisine fonctionne ; le serveur (libc) traduit en commande précise pour la cuisine (syscall write). Mais le serveur reste en salle, il ne cuisine pas.

5. Conséquence (question c3)

Le noyau, lui, ne peut pas utiliser la libc : la libc repose sur les syscalls… qui sont fournis par le noyau lui-même. Ce serait la cuisine qui passe commande au serveur pour se servir elle-même. Donc le noyau a ses propres fonctions : printk() au lieu de printf(), son propre allocateur au lieu de malloc(), etc. (dans so3/so3/lib/).
<br><br>

d) Trouver le chemin du dossier contenant le code de support des architectures processeur (jeu d'instructions) prises en charge par SO3. Quelles sont-elles ?

Le code de support des architectures se trouve dans `so3/so3/arch/`. SO3 prend en charge deux architectures ARM :
- `arm32/` : ARM 32 bits (ARMv7, jeu d'instructions AArch32) — celle utilisée dans ce labo (QEMU émule un Cortex-A15) ;
- `arm64/` : ARM 64 bits (ARMv8, jeu d'instructions AArch64).

Étape 5 — Manipulation mémoire (byte à byte)

