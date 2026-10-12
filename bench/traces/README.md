# bench/traces/ — traces de référence du gate de performance

Chaque fichier `*.csv` de ce dossier est un **jeu de référence** : la CI
(`.github/workflows/bench-gate.yml`) analyse sa trace avec `bench-fps.sh` et
**bloque la release si le 1% low passe sous 30 FPS**.

```
bench/traces/
├── reference-merguez-30fps.csv      ← jeu de référence (gate : doit passer)
└── examples/
    └── example-stutter-fail.csv     ← exemple volontairement raté (hors gate,
                                        sert à démontrer le blocage)
```

## Format des traces

CSV avec en-tête, une ligne par image ; `bench-fps.sh` auto-détecte la colonne
`frametime` (ms) ou `fps` :

```csv
fps,frametime
40.0,25.0
32.26,31.0
```

## Enregistrer une vraie trace (sur machine réelle, avec MangoHud)

```bash
# Lancer le jeu avec journalisation des frametimes
MANGOHUD_CONFIG="log_interval=0,log_file=mon-jeu.csv,output_folder=$PWD" \
  mangohud %command%

# Vérifier la trace, puis l'ajouter au gate
scripts/bench-fps.sh analyse --input mon-jeu.csv --game "Mon Jeu" --floor 30
cp mon-jeu.csv bench/traces/mon-jeu.csv   # → devient un jeu de référence
```

## Ajouter / retirer un jeu de référence

- **Ajouter** : déposer `bench/traces/<nom>.csv` — la CI le découvre automatiquement.
- **Retirer** : déplacer le fichier dans `bench/traces/examples/` (il sort du gate).

## Vérifier le gate en local

```bash
scripts/bench-fps.sh analyse --input bench/traces/reference-merguez-30fps.csv \
  --game ref --floor 30      # exit 0  → la release passerait
scripts/bench-fps.sh analyse --input bench/traces/examples/example-stutter-fail.csv \
  --game fail --floor 30     # exit 10 → la release serait bloquée
```
