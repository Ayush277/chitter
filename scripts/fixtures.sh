#!/bin/bash
# Generates multilingual speech fixtures offline with macOS `say` (+ afconvert to 16 kHz mono WAV).
set -e
cd "$(dirname "$0")/.."
OUT=Resources/Fixtures; mkdir -p "$OUT"
gen() { # name voice text
  say -v "$2" -o "$OUT/$1.aiff" "$3" 2>/dev/null || { echo "skip $1 (voice $2 missing)"; return; }
  afconvert -f WAVE -d LEI16@16000 -c 1 "$OUT/$1.aiff" "$OUT/$1.wav" && rm "$OUT/$1.aiff"
  echo "$3" > "$OUT/$1.txt"; echo "ok $1"
}
gen en "Samantha" "Welcome everyone to the weekly planning meeting. Today we will review the launch schedule and decide who owns each task. Maria will send the budget report by Friday. We agreed to move the release to the first of March."
gen es "Monica"   "Buenos días a todos. Hoy vamos a revisar el calendario del proyecto y decidir quién se encarga de cada tarea."
gen zh "Tingting" "大家好，今天我们来讨论一下项目的进度，并决定下周的工作安排。"
gen ja "Kyoko"    "皆さん、おはようございます。今日はプロジェクトの進捗について話し合います。"
gen fr "Thomas"   "Bonjour à tous. Aujourd'hui nous allons examiner le calendrier du projet et décider qui s'occupe de chaque tâche."
# Sample meeting for onboarding (F18): a short two-speaker style dialogue read by two voices, concatenated.
gen sample1 "Samantha" "Let's start with the launch date. I think we should move the release to the first of March because testing is not finished."
gen sample2 "Daniel"   "Agreed. I will ask the design team to finish the onboarding screens by next Wednesday. Also, Priya needs to update the privacy policy before launch."
gen sample3 "Samantha" "Great. To summarize, we decided to move the release to March first. Daniel will follow up with design, and Priya owns the privacy policy."
ls -la "$OUT"
