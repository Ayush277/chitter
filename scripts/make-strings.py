#!/usr/bin/env python3
"""Scans Swift sources for UI string literals and (re)generates Resources/Localizable.xcstrings.
English is the source. ES / ZH-Hans / JA / KO values are machine-translated stubs marked `needs_review`;
strings without a stub fall back to English at runtime."""
import json, re, pathlib, sys
root = pathlib.Path(__file__).resolve().parent.parent
pat = re.compile(r'\b(?:Text|Button|Label|Toggle|Section|Picker|LabeledContent|TextField|SecureField|Menu|GroupBox|Stepper|L)\(\s*"((?:[^"\\\n]|\\.)*)"')
keys = set()
for f in (root / "Sources").rglob("*.swift"):
    for m in pat.finditer(f.read_text()):
        s = m.group(1)
        if "\\(" in s or not s.strip() or len(s) < 2: continue
        keys.add(s.replace('\\"', '"'))
T = {  # key: (es, zh-Hans, ja, ko)
 "Welcome to Chitter": ("Te damos la bienvenida a Chitter", "欢迎使用 Chitter", "Chitter へようこそ", "Chitter에 오신 것을 환영합니다"),
 "Audio": ("Audio", "音频", "オーディオ", "오디오"),
 "Language": ("Idioma", "语言", "言語", "언어"),
 "Notes engine": ("Motor de notas", "笔记引擎", "ノートエンジン", "노트 엔진"),
 "Try a sample": ("Prueba un ejemplo", "试试示例", "サンプルを試す", "샘플 체험"),
 "Let Chitter hear your Mac": ("Deja que Chitter escuche tu Mac", "让 Chitter 听到你的 Mac", "Chitter に Mac の音を聞かせる", "Chitter가 Mac의 소리를 듣게 하기"),
 "Allow system audio": ("Permitir audio del sistema", "允许系统音频", "システムオーディオを許可", "시스템 오디오 허용"),
 "Next": ("Siguiente", "下一步", "次へ", "다음"),
 "Back": ("Atrás", "返回", "戻る", "뒤로"),
 "Done": ("Listo", "完成", "完了", "완료"),
 "Settings…": ("Ajustes…", "设置…", "設定…", "설정…"),
 "Privacy Ledger…": ("Registro de privacidad…", "隐私账本…", "プライバシー台帳…", "개인정보 원장…"),
 "Welcome tour": ("Visita de bienvenida", "欢迎导览", "ウェルカムツアー", "시작 가이드"),
 "Languages": ("Idiomas", "语言", "言語", "언어"),
 "Engines": ("Motores", "引擎", "エンジン", "엔진"),
 "Hotkeys": ("Atajos", "快捷键", "ホットキー", "단축키"),
 "Storage": ("Almacenamiento", "存储", "ストレージ", "저장소"),
 "Privacy": ("Privacidad", "隐私", "プライバシー", "개인정보"),
 "Accessibility": ("Accesibilidad", "辅助功能", "アクセシビリティ", "손쉬운 사용"),
 "About": ("Acerca de", "关于", "概要", "정보"),
 "Subtitles": ("Subtítulos", "字幕", "字幕", "자막"),
 "Detect automatically": ("Detectar automáticamente", "自动检测", "自動検出", "자동 감지"),
 "Language being spoken": ("Idioma que se habla", "说话语言", "話されている言語", "사용 중인 언어"),
 "Show translation in": ("Mostrar traducción en", "翻译显示为", "翻訳の表示言語", "번역 표시 언어"),
 "Write notes": ("Escribir notas", "生成笔记", "ノートを作成", "노트 작성"),
 "Writing notes…": ("Escribiendo notas…", "正在生成笔记…", "ノートを作成中…", "노트 작성 중…"),
 "Copy as Markdown": ("Copiar como Markdown", "复制为 Markdown", "Markdown としてコピー", "Markdown으로 복사"),
 "Export": ("Exportar", "导出", "書き出し", "내보내기"),
 "Summary": ("Resumen", "摘要", "要約", "요약"),
 "Decisions": ("Decisiones", "决定", "決定事項", "결정 사항"),
 "Action items": ("Tareas", "待办事项", "アクション項目", "실행 항목"),
 "Topics": ("Temas", "主题", "トピック", "주제"),
 "Glossary": ("Glosario", "术语表", "用語集", "용어집"),
 "Meetings": ("Reuniones", "会议", "ミーティング", "회의"),
 "Search all meetings": ("Buscar en todas las reuniones", "搜索所有会议", "すべてのミーティングを検索", "모든 회의 검색"),
 "Nothing left your Mac.": ("Nada salió de tu Mac.", "没有任何内容离开你的 Mac。", "Mac の外には何も送信されていません。", "Mac 밖으로 나간 것은 없습니다."),
 "Time": ("Hora", "时间", "時刻", "시간"),
 "Host": ("Host", "主机", "ホスト", "호스트"),
 "Sent": ("Enviado", "已发送", "送信", "보냄"),
 "Received": ("Recibido", "已接收", "受信", "받음"),
 "Why": ("Motivo", "目的", "理由", "이유"),
 "Provider": ("Proveedor", "提供方", "プロバイダ", "제공자"),
 "Start listening  (⌃⌥R)": ("Empezar a escuchar  (⌃⌥R)", "开始聆听  (⌃⌥R)", "聞き取りを開始  (⌃⌥R)", "듣기 시작  (⌃⌥R)"),
 "Stop listening  (⌃⌥R)": ("Dejar de escuchar  (⌃⌥R)", "停止聆听  (⌃⌥R)", "聞き取りを停止  (⌃⌥R)", "듣기 중지  (⌃⌥R)"),
 "Try the sample meeting": ("Probar la reunión de ejemplo", "试用示例会议", "サンプル会議を試す", "샘플 회의 체험"),
 "Quit Chitter": ("Salir de Chitter", "退出 Chitter", "Chitter を終了", "Chitter 종료"),
}
strings = {}
for k in sorted(keys | set(T)):
    loc = {"en": {"stringUnit": {"state": "translated", "value": k}}}
    for i, lang in enumerate(["es", "zh-Hans", "ja", "ko"]):
        v = T[k][i] if k in T else k
        loc[lang] = {"stringUnit": {"state": "needs_review", "value": v}}
    strings[k] = {"extractionState": "manual", "localizations": loc}
out = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
(root / "Resources" / "Localizable.xcstrings").write_text(json.dumps(out, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
translated = sum(1 for k in strings if k in T)
print(f"{len(strings)} strings, {translated} with ES/ZH/JA/KO stubs (all marked needs_review)")
