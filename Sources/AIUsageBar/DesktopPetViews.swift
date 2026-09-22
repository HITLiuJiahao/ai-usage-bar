import AppKit
import SwiftUI

enum PetUI {
    private static let additionalTranslations: [AppLanguage: [String: String]] = [
        .traditionalChinese: [
            "Cat": "小貓", "Bear": "小熊", "Fox": "小狐狸", "Starting task": "正在啟動任務", "Thinking": "思考中", "Running a command": "執行命令中", "Editing files": "修改檔案中", "Reading files": "讀取檔案中", "Searching the web": "搜尋網頁中", "Calling a tool": "呼叫工具中", "Waiting for input": "等待輸入", "Hatchling": "初生", "Companion": "夥伴", "Scout": "探索者", "Hero": "英雄", "Legend": "傳說", "First completion": "第一次完成", "10 completions": "完成 10 次", "50 completions": "完成 50 次", "100 completions": "完成 100 次", "1M tokens": "100 萬 Token", "10M tokens": "1000 萬 Token", "50M tokens": "5000 萬 Token", "Level 5": "等級 5", "Level 10": "等級 10", "Level 20": "等級 20", "3-day streak": "連續 3 天", "7-day streak": "連續 7 天", "Night owl": "夜貓子", "Early bird": "早起鳥", "Show Pet HUD": "查看寵物面板", "Feed": "餵一餵", "Hide Desktop Pet": "隱藏桌面寵物", "Blocked": "受阻", "Waiting": "等待", "more agents": "更多 Agent", "Level": "等級", "Growth": "成長", "Energy": "能量", "active-day streak": "連續活躍天數", "completed": "已完成", "Seven-day activity": "最近 7 天活躍度", "Active agents": "正在執行的 Agent", "Hide": "隱藏", "View all": "查看全部", "Live quotas": "即時額度", "Show desktop pet": "顯示桌面寵物", "Show Now": "立即顯示", "Open Pet HUD": "查看寵物面板", "Reset Position": "重設位置", "Pet Shortcuts": "寵物快捷鍵", "Restore Defaults": "恢復預設", "Size": "大小", "Opacity": "不透明度", "Show status bubbles": "顯示狀態氣泡", "Play notification sounds": "播放通知聲音", "Break reminders": "久坐休息提醒", "Reminder interval": "提醒間隔", "min": "分鐘", "Current pet": "目前寵物", "Import Pet Pack…": "匯入寵物包…", "Use project-specific pets": "依專案使用專屬寵物", "Custom bubble messages": "自訂氣泡文案", "Idle": "閒置時", "Working": "工作時", "Waiting or blocked": "等待或受阻時", "Completed": "完成時", "Agent Hook Bridge": "Agent Hook 橋接", "Copy Example Command": "複製範例命令", "Achievements": "成就", "Session History": "工作階段歷史", "Clear Pet Progress": "清除寵物成長記錄", "Clear": "清除", "OK": "知道了", "Don't Remind Me Again": "不再提示", "Desktop Pet": "桌面寵物"
        ],
        .spanish: [
            "Cat": "Gato", "Bear": "Oso", "Fox": "Zorro", "Starting task": "Iniciando tarea", "Thinking": "Pensando", "Running a command": "Ejecutando un comando", "Editing files": "Editando archivos", "Reading files": "Leyendo archivos", "Searching the web": "Buscando en la web", "Calling a tool": "Llamando a una herramienta", "Waiting for input": "Esperando entrada", "Hatchling": "Cría", "Companion": "Compañero", "Scout": "Explorador", "Hero": "Héroe", "Legend": "Leyenda", "First completion": "Primera finalización", "10 completions": "10 finalizaciones", "50 completions": "50 finalizaciones", "100 completions": "100 finalizaciones", "1M tokens": "1 M de tokens", "10M tokens": "10 M de tokens", "50M tokens": "50 M de tokens", "Level 5": "Nivel 5", "Level 10": "Nivel 10", "Level 20": "Nivel 20", "3-day streak": "Racha de 3 días", "7-day streak": "Racha de 7 días", "Night owl": "Noctámbulo", "Early bird": "Madrugador", "Show Pet HUD": "Ver panel de mascota", "Feed": "Dar de comer", "Hide Desktop Pet": "Ocultar mascota de escritorio", "Blocked": "Bloqueado", "Waiting": "Esperando", "more agents": "más agentes", "Level": "Nivel", "Growth": "Crecimiento", "Energy": "Energía", "active-day streak": "racha de días activos", "completed": "completadas", "Seven-day activity": "Actividad de los últimos 7 días", "Active agents": "Agentes activos", "Hide": "Ocultar", "View all": "Ver todo", "Live quotas": "Cuotas en tiempo real", "Show desktop pet": "Mostrar mascota de escritorio", "Show Now": "Mostrar ahora", "Open Pet HUD": "Abrir panel de mascota", "Reset Position": "Restablecer posición", "Pet Shortcuts": "Atajos de mascota", "Restore Defaults": "Restaurar valores por defecto", "Size": "Tamaño", "Opacity": "Opacidad", "Show status bubbles": "Mostrar burbujas de estado", "Play notification sounds": "Reproducir sonidos de notificación", "Break reminders": "Recordatorios de descanso", "Reminder interval": "Intervalo del recordatorio", "min": "min", "Current pet": "Mascota actual", "Import Pet Pack…": "Importar paquete de mascota…", "Use project-specific pets": "Usar mascotas por proyecto", "Custom bubble messages": "Mensajes de burbuja personalizados", "Idle": "Inactivo", "Working": "Trabajando", "Waiting or blocked": "En espera o bloqueado", "Completed": "Completado", "Agent Hook Bridge": "Puente de Agent Hook", "Copy Example Command": "Copiar comando de ejemplo", "Session History": "Historial de sesiones", "Clear Pet Progress": "Borrar progreso de la mascota", "Clear": "Borrar", "OK": "Aceptar", "Don't Remind Me Again": "No volver a avisar", "Desktop Pet": "Mascota de escritorio"
        ],
        .french: [
            "Cat": "Chat", "Bear": "Ours", "Fox": "Renard", "Starting task": "Démarrage de la tâche", "Thinking": "Réflexion", "Running a command": "Exécution d’une commande", "Editing files": "Modification des fichiers", "Reading files": "Lecture des fichiers", "Searching the web": "Recherche sur le Web", "Calling a tool": "Appel d’un outil", "Waiting for input": "En attente d’une saisie", "Hatchling": "Nouveau-né", "Companion": "Compagnon", "Scout": "Éclaireur", "Hero": "Héros", "Legend": "Légende", "First completion": "Première réussite", "10 completions": "10 réussites", "50 completions": "50 réussites", "100 completions": "100 réussites", "1M tokens": "1 M de tokens", "10M tokens": "10 M de tokens", "50M tokens": "50 M de tokens", "Level 5": "Niveau 5", "Level 10": "Niveau 10", "Level 20": "Niveau 20", "3-day streak": "Série de 3 jours", "7-day streak": "Série de 7 jours", "Night owl": "Oiseau de nuit", "Early bird": "Lève-tôt", "Show Pet HUD": "Voir le panneau du compagnon", "Feed": "Nourrir", "Hide Desktop Pet": "Masquer le compagnon de bureau", "Blocked": "Bloqué", "Waiting": "En attente", "more agents": "agents supplémentaires", "Level": "Niveau", "Growth": "Progression", "Energy": "Énergie", "active-day streak": "série de jours actifs", "completed": "terminées", "Seven-day activity": "Activité des 7 derniers jours", "Active agents": "Agents actifs", "Achievements": "Succès", "Hide": "Masquer", "View all": "Tout afficher", "Live quotas": "Quotas en direct", "Show desktop pet": "Afficher le compagnon de bureau", "Show Now": "Afficher maintenant", "Open Pet HUD": "Ouvrir le panneau du compagnon", "Reset Position": "Réinitialiser la position", "Pet Shortcuts": "Raccourcis du compagnon", "Restore Defaults": "Rétablir les valeurs par défaut", "Size": "Taille", "Opacity": "Opacité", "Show status bubbles": "Afficher les bulles d’état", "Play notification sounds": "Lire les sons de notification", "Break reminders": "Rappels de pause", "Reminder interval": "Intervalle du rappel", "min": "min", "Current pet": "Compagnon actuel", "Import Pet Pack…": "Importer un pack de compagnon…", "Use project-specific pets": "Utiliser un compagnon par projet", "Custom bubble messages": "Messages de bulle personnalisés", "Idle": "Inactif", "Working": "En cours", "Waiting or blocked": "En attente ou bloqué", "Completed": "Terminé", "Agent Hook Bridge": "Pont Agent Hook", "Copy Example Command": "Copier la commande exemple", "Session History": "Historique des sessions", "Clear Pet Progress": "Effacer la progression du compagnon", "Clear": "Effacer", "OK": "OK", "Don't Remind Me Again": "Ne plus me le rappeler", "Desktop Pet": "Compagnon de bureau"
        ],
        .german: [
            "Cat": "Katze", "Bear": "Bär", "Fox": "Fuchs", "Starting task": "Aufgabe wird gestartet", "Thinking": "Denken", "Running a command": "Befehl wird ausgeführt", "Editing files": "Dateien werden bearbeitet", "Reading files": "Dateien werden gelesen", "Searching the web": "Websuche", "Calling a tool": "Tool wird aufgerufen", "Waiting for input": "Warten auf Eingabe", "Hatchling": "Jungtier", "Companion": "Begleiter", "Scout": "Späher", "Hero": "Held", "Legend": "Legende", "First completion": "Erster Abschluss", "10 completions": "10 Abschlüsse", "50 completions": "50 Abschlüsse", "100 completions": "100 Abschlüsse", "1M tokens": "1 Mio. Tokens", "10M tokens": "10 Mio. Tokens", "50M tokens": "50 Mio. Tokens", "Level 5": "Stufe 5", "Level 10": "Stufe 10", "Level 20": "Stufe 20", "3-day streak": "3-Tage-Serie", "7-day streak": "7-Tage-Serie", "Night owl": "Nachteule", "Early bird": "Frühaufsteher", "Show Pet HUD": "Haustier-Panel anzeigen", "Feed": "Füttern", "Hide Desktop Pet": "Desktop-Haustier ausblenden", "Blocked": "Blockiert", "Waiting": "Wartet", "more agents": "weitere Agenten", "Level": "Stufe", "Growth": "Wachstum", "Energy": "Energie", "active-day streak": "Serie aktiver Tage", "completed": "abgeschlossen", "Seven-day activity": "Aktivität der letzten 7 Tage", "Active agents": "Aktive Agenten", "Achievements": "Erfolge", "Hide": "Ausblenden", "View all": "Alle anzeigen", "Live quotas": "Live-Kontingente", "Show desktop pet": "Desktop-Haustier anzeigen", "Show Now": "Jetzt anzeigen", "Open Pet HUD": "Haustier-Panel öffnen", "Reset Position": "Position zurücksetzen", "Pet Shortcuts": "Haustier-Tastenkürzel", "Restore Defaults": "Standard wiederherstellen", "Size": "Größe", "Opacity": "Deckkraft", "Show status bubbles": "Statusblasen anzeigen", "Play notification sounds": "Hinweistöne abspielen", "Break reminders": "Pausenerinnerungen", "Reminder interval": "Erinnerungsintervall", "min": "Min.", "Current pet": "Aktuelles Haustier", "Import Pet Pack…": "Haustierpaket importieren…", "Use project-specific pets": "Projektbezogene Haustiere verwenden", "Custom bubble messages": "Eigene Blasentexte", "Idle": "Inaktiv", "Working": "Arbeitet", "Waiting or blocked": "Wartet oder blockiert", "Completed": "Abgeschlossen", "Agent Hook Bridge": "Agent-Hook-Brücke", "Copy Example Command": "Beispielbefehl kopieren", "Session History": "Sitzungsverlauf", "Clear Pet Progress": "Haustierfortschritt löschen", "Clear": "Löschen", "OK": "OK", "Don't Remind Me Again": "Nicht mehr erinnern", "Desktop Pet": "Desktop-Haustier"
        ],
        .italian: [
            "Cat": "Gatto", "Bear": "Orso", "Fox": "Volpe", "Starting task": "Avvio attività", "Thinking": "Ragionamento", "Running a command": "Esecuzione comando", "Editing files": "Modifica file", "Reading files": "Lettura file", "Searching the web": "Ricerca sul web", "Calling a tool": "Chiamata strumento", "Waiting for input": "In attesa di input", "Hatchling": "Cucciolo", "Companion": "Compagno", "Scout": "Esploratore", "Hero": "Eroe", "Legend": "Leggenda", "First completion": "Prima conclusione", "10 completions": "10 conclusioni", "50 completions": "50 conclusioni", "100 completions": "100 conclusioni", "1M tokens": "1 M di token", "10M tokens": "10 M di token", "50M tokens": "50 M di token", "Level 5": "Livello 5", "Level 10": "Livello 10", "Level 20": "Livello 20", "3-day streak": "Serie di 3 giorni", "7-day streak": "Serie di 7 giorni", "Night owl": "Nottambulo", "Early bird": "Mattiniero", "Show Pet HUD": "Mostra pannello mascotte", "Feed": "Nutri", "Hide Desktop Pet": "Nascondi mascotte desktop", "Blocked": "Bloccato", "Waiting": "In attesa", "more agents": "altri agenti", "Level": "Livello", "Growth": "Crescita", "Energy": "Energia", "active-day streak": "serie di giorni attivi", "completed": "completate", "Seven-day activity": "Attività degli ultimi 7 giorni", "Active agents": "Agenti attivi", "Achievements": "Obiettivi", "Hide": "Nascondi", "View all": "Mostra tutto", "Live quotas": "Quote in tempo reale", "Show desktop pet": "Mostra mascotte desktop", "Show Now": "Mostra ora", "Open Pet HUD": "Apri pannello mascotte", "Reset Position": "Reimposta posizione", "Pet Shortcuts": "Scorciatoie mascotte", "Restore Defaults": "Ripristina default", "Size": "Dimensioni", "Opacity": "Opacità", "Show status bubbles": "Mostra fumetti di stato", "Play notification sounds": "Riproduci suoni delle notifiche", "Break reminders": "Promemoria pausa", "Reminder interval": "Intervallo promemoria", "min": "min", "Current pet": "Mascotte attuale", "Import Pet Pack…": "Importa pacchetto mascotte…", "Use project-specific pets": "Usa mascotte per progetto", "Custom bubble messages": "Messaggi personalizzati", "Idle": "Inattivo", "Working": "Al lavoro", "Waiting or blocked": "In attesa o bloccato", "Completed": "Completato", "Agent Hook Bridge": "Bridge Agent Hook", "Copy Example Command": "Copia comando di esempio", "Session History": "Cronologia sessioni", "Clear Pet Progress": "Cancella progressi mascotte", "Clear": "Cancella", "OK": "OK", "Don't Remind Me Again": "Non ricordarmelo più", "Desktop Pet": "Mascotte desktop"
        ],
        .portugueseBrazil: [
            "Cat": "Gato", "Bear": "Urso", "Fox": "Raposa", "Starting task": "Iniciando tarefa", "Thinking": "Pensando", "Running a command": "Executando um comando", "Editing files": "Editando arquivos", "Reading files": "Lendo arquivos", "Searching the web": "Pesquisando na web", "Calling a tool": "Chamando uma ferramenta", "Waiting for input": "Aguardando entrada", "Hatchling": "Filhote", "Companion": "Companheiro", "Scout": "Explorador", "Hero": "Herói", "Legend": "Lenda", "First completion": "Primeira conclusão", "10 completions": "10 conclusões", "50 completions": "50 conclusões", "100 completions": "100 conclusões", "1M tokens": "1 mi de tokens", "10M tokens": "10 mi de tokens", "50M tokens": "50 mi de tokens", "Level 5": "Nível 5", "Level 10": "Nível 10", "Level 20": "Nível 20", "3-day streak": "Sequência de 3 dias", "7-day streak": "Sequência de 7 dias", "Night owl": "Coruja noturna", "Early bird": "Madrugador", "Show Pet HUD": "Ver painel do mascote", "Feed": "Alimentar", "Hide Desktop Pet": "Ocultar mascote da área de trabalho", "Blocked": "Bloqueado", "Waiting": "Aguardando", "more agents": "mais agentes", "Level": "Nível", "Growth": "Crescimento", "Energy": "Energia", "active-day streak": "sequência de dias ativos", "completed": "concluídas", "Seven-day activity": "Atividade dos últimos 7 dias", "Active agents": "Agentes ativos", "Achievements": "Conquistas", "Hide": "Ocultar", "View all": "Ver tudo", "Live quotas": "Cotas em tempo real", "Show desktop pet": "Mostrar mascote da área de trabalho", "Show Now": "Mostrar agora", "Open Pet HUD": "Abrir painel do mascote", "Reset Position": "Redefinir posição", "Pet Shortcuts": "Atalhos do mascote", "Restore Defaults": "Restaurar padrões", "Size": "Tamanho", "Opacity": "Opacidade", "Show status bubbles": "Mostrar balões de status", "Play notification sounds": "Reproduzir sons de notificação", "Break reminders": "Lembretes de pausa", "Reminder interval": "Intervalo do lembrete", "min": "min", "Current pet": "Mascote atual", "Import Pet Pack…": "Importar pacote de mascote…", "Use project-specific pets": "Usar mascotes por projeto", "Custom bubble messages": "Mensagens personalizadas", "Idle": "Inativo", "Working": "Trabalhando", "Waiting or blocked": "Aguardando ou bloqueado", "Completed": "Concluído", "Agent Hook Bridge": "Ponte do Agent Hook", "Copy Example Command": "Copiar comando de exemplo", "Session History": "Histórico de sessões", "Clear Pet Progress": "Limpar progresso do mascote", "Clear": "Limpar", "OK": "OK", "Don't Remind Me Again": "Não lembrar novamente", "Desktop Pet": "Mascote da área de trabalho"
        ],
        .russian: [
            "Cat": "Кошка", "Bear": "Медведь", "Fox": "Лиса", "Starting task": "Запуск задачи", "Thinking": "Размышление", "Running a command": "Выполнение команды", "Editing files": "Изменение файлов", "Reading files": "Чтение файлов", "Searching the web": "Поиск в интернете", "Calling a tool": "Вызов инструмента", "Waiting for input": "Ожидание ввода", "Hatchling": "Малыш", "Companion": "Спутник", "Scout": "Разведчик", "Hero": "Герой", "Legend": "Легенда", "First completion": "Первое завершение", "10 completions": "10 завершений", "50 completions": "50 завершений", "100 completions": "100 завершений", "1M tokens": "1 млн токенов", "10M tokens": "10 млн токенов", "50M tokens": "50 млн токенов", "Level 5": "Уровень 5", "Level 10": "Уровень 10", "Level 20": "Уровень 20", "3-day streak": "Серия из 3 дней", "7-day streak": "Серия из 7 дней", "Night owl": "Ночная сова", "Early bird": "Ранняя пташка", "Show Pet HUD": "Открыть панель питомца", "Feed": "Покормить", "Hide Desktop Pet": "Скрыть питомца", "Blocked": "Заблокировано", "Waiting": "Ожидание", "more agents": "ещё агентов", "Level": "Уровень", "Growth": "Развитие", "Energy": "Энергия", "active-day streak": "серия активных дней", "completed": "завершено", "Seven-day activity": "Активность за 7 дней", "Active agents": "Активные агенты", "Achievements": "Достижения", "Hide": "Скрыть", "View all": "Показать всё", "Live quotas": "Текущие лимиты", "Show desktop pet": "Показать питомца", "Show Now": "Показать сейчас", "Open Pet HUD": "Открыть панель питомца", "Reset Position": "Сбросить положение", "Pet Shortcuts": "Сочетания клавиш питомца", "Restore Defaults": "Восстановить по умолчанию", "Size": "Размер", "Opacity": "Непрозрачность", "Show status bubbles": "Показывать пузыри статуса", "Play notification sounds": "Воспроизводить звуки уведомлений", "Break reminders": "Напоминания о перерыве", "Reminder interval": "Интервал напоминания", "min": "мин", "Current pet": "Текущий питомец", "Import Pet Pack…": "Импортировать пакет питомца…", "Use project-specific pets": "Использовать питомца для проекта", "Custom bubble messages": "Свои сообщения в пузырях", "Idle": "Неактивен", "Working": "Работает", "Waiting or blocked": "Ожидание или блокировка", "Completed": "Завершено", "Agent Hook Bridge": "Мост Agent Hook", "Copy Example Command": "Скопировать пример команды", "Session History": "История сеансов", "Clear Pet Progress": "Очистить развитие питомца", "Clear": "Очистить", "OK": "ОК", "Don't Remind Me Again": "Больше не напоминать", "Desktop Pet": "Питомец на рабочем столе"
        ]
    ]

    private static let statusTranslations: [AppLanguage: [String: String]] = [
        .traditionalChinese: [
            "I’m here with you.": "我會陪著你。", "is working": "正在工作", "Needs your attention.": "需要你的注意。", "Task blocked. Needs attention.": "任務受阻，需要處理。", "Task complete. Nicely done!": "任務完成，做得好！", "Energy restored!": "能量補充好了！", "Taking a quiet moment.": "我也在休息。", "You’ve been at it a while — take a short break.": "已經專心一段時間了，休息一下吧。", "Choose a pet pack folder containing pet.json and a transparent PNG sprite": "選擇包含 pet.json 與透明 PNG 精靈圖的寵物包資料夾", "Import Pet Pack": "匯入寵物包", "This pet pack is missing a valid pet.json or sprite.": "這個寵物包缺少有效的 pet.json 或精靈圖。", "A new companion joined!": "新夥伴加入了！", "Couldn’t import that pet pack.": "無法匯入這個寵物包。", "Choose a project folder for a dedicated pet": "選擇要綁定專屬寵物的專案資料夾", "Add Project": "新增專案"
        ],
        .spanish: [
            "I’m here with you.": "Estoy aquí contigo.", "is working": "está trabajando", "Needs your attention.": "Necesita tu atención.", "Task blocked. Needs attention.": "Tarea bloqueada. Necesita atención.", "Task complete. Nicely done!": "Tarea completada. ¡Bien hecho!", "Energy restored!": "¡Energía restaurada!", "Taking a quiet moment.": "Tomándome un momento de calma.", "You’ve been at it a while — take a short break.": "Llevas un rato trabajando; tómate un breve descanso.", "Choose a pet pack folder containing pet.json and a transparent PNG sprite": "Elige una carpeta de mascota con pet.json y un sprite PNG transparente", "Import Pet Pack": "Importar paquete de mascota", "This pet pack is missing a valid pet.json or sprite.": "Falta un pet.json o sprite válido en este paquete.", "A new companion joined!": "¡Se ha unido un nuevo compañero!", "Couldn’t import that pet pack.": "No se pudo importar el paquete de mascota.", "Choose a project folder for a dedicated pet": "Elige una carpeta de proyecto para una mascota dedicada", "Add Project": "Añadir proyecto"
        ],
        .french: [
            "I’m here with you.": "Je suis là avec vous.", "is working": "travaille", "Needs your attention.": "Votre attention est nécessaire.", "Task blocked. Needs attention.": "Tâche bloquée. Votre attention est nécessaire.", "Task complete. Nicely done!": "Tâche terminée. Bravo !", "Energy restored!": "Énergie restaurée !", "Taking a quiet moment.": "Je prends un moment de calme.", "You’ve been at it a while — take a short break.": "Vous travaillez depuis un moment : faites une courte pause.", "Choose a pet pack folder containing pet.json and a transparent PNG sprite": "Choisissez un dossier contenant pet.json et un sprite PNG transparent", "Import Pet Pack": "Importer un pack de compagnon", "This pet pack is missing a valid pet.json or sprite.": "Ce pack ne contient pas de pet.json ou de sprite valide.", "A new companion joined!": "Un nouveau compagnon vous a rejoint !", "Couldn’t import that pet pack.": "Impossible d’importer ce pack de compagnon.", "Choose a project folder for a dedicated pet": "Choisissez un dossier de projet pour un compagnon dédié", "Add Project": "Ajouter un projet"
        ],
        .german: [
            "I’m here with you.": "Ich bin bei dir.", "is working": "arbeitet", "Needs your attention.": "Braucht deine Aufmerksamkeit.", "Task blocked. Needs attention.": "Aufgabe blockiert. Aufmerksamkeit erforderlich.", "Task complete. Nicely done!": "Aufgabe erledigt. Gut gemacht!", "Energy restored!": "Energie wiederhergestellt!", "Taking a quiet moment.": "Ich mache gerade einen ruhigen Moment Pause.", "You’ve been at it a while — take a short break.": "Du arbeitest schon eine Weile – mach eine kurze Pause.", "Choose a pet pack folder containing pet.json and a transparent PNG sprite": "Wähle einen Haustierordner mit pet.json und einem transparenten PNG-Sprite", "Import Pet Pack": "Haustierpaket importieren", "This pet pack is missing a valid pet.json or sprite.": "Diesem Paket fehlt eine gültige pet.json oder ein Sprite.", "A new companion joined!": "Ein neuer Begleiter ist da!", "Couldn’t import that pet pack.": "Das Haustierpaket konnte nicht importiert werden.", "Choose a project folder for a dedicated pet": "Wähle einen Projektordner für ein eigenes Haustier", "Add Project": "Projekt hinzufügen"
        ],
        .italian: [
            "I’m here with you.": "Sono qui con te.", "is working": "sta lavorando", "Needs your attention.": "Richiede la tua attenzione.", "Task blocked. Needs attention.": "Attività bloccata. Serve la tua attenzione.", "Task complete. Nicely done!": "Attività completata. Ben fatto!", "Energy restored!": "Energia ripristinata!", "Taking a quiet moment.": "Mi prendo un momento di calma.", "You’ve been at it a while — take a short break.": "Lavori da un po’: fai una breve pausa.", "Choose a pet pack folder containing pet.json and a transparent PNG sprite": "Scegli una cartella con pet.json e uno sprite PNG trasparente", "Import Pet Pack": "Importa pacchetto mascotte", "This pet pack is missing a valid pet.json or sprite.": "Il pacchetto non contiene un pet.json o uno sprite valido.", "A new companion joined!": "È arrivato un nuovo compagno!", "Couldn’t import that pet pack.": "Impossibile importare il pacchetto mascotte.", "Choose a project folder for a dedicated pet": "Scegli una cartella di progetto per una mascotte dedicata", "Add Project": "Aggiungi progetto"
        ],
        .portugueseBrazil: [
            "I’m here with you.": "Estou aqui com você.", "is working": "está trabalhando", "Needs your attention.": "Precisa da sua atenção.", "Task blocked. Needs attention.": "Tarefa bloqueada. Precisa de atenção.", "Task complete. Nicely done!": "Tarefa concluída. Muito bem!", "Energy restored!": "Energia restaurada!", "Taking a quiet moment.": "Vou fazer uma pausa tranquila.", "You’ve been at it a while — take a short break.": "Você está trabalhando há um tempo; faça uma pausa curta.", "Choose a pet pack folder containing pet.json and a transparent PNG sprite": "Escolha uma pasta com pet.json e um sprite PNG transparente", "Import Pet Pack": "Importar pacote de mascote", "This pet pack is missing a valid pet.json or sprite.": "Este pacote não tem um pet.json ou sprite válido.", "A new companion joined!": "Um novo companheiro chegou!", "Couldn’t import that pet pack.": "Não foi possível importar o pacote de mascote.", "Choose a project folder for a dedicated pet": "Escolha uma pasta de projeto para um mascote dedicado", "Add Project": "Adicionar projeto"
        ],
        .russian: [
            "I’m here with you.": "Я рядом с тобой.", "is working": "работает", "Needs your attention.": "Требуется ваше внимание.", "Task blocked. Needs attention.": "Задача заблокирована. Требуется внимание.", "Task complete. Nicely done!": "Задача завершена. Отлично!", "Energy restored!": "Энергия восстановлена!", "Taking a quiet moment.": "Я немного отдыхаю.", "You’ve been at it a while — take a short break.": "Вы уже долго работаете — сделайте небольшой перерыв.", "Choose a pet pack folder containing pet.json and a transparent PNG sprite": "Выберите папку с pet.json и прозрачным PNG-спрайтом", "Import Pet Pack": "Импортировать пакет питомца", "This pet pack is missing a valid pet.json or sprite.": "В пакете нет корректного pet.json или спрайта.", "A new companion joined!": "Новый спутник присоединился!", "Couldn’t import that pet pack.": "Не удалось импортировать пакет питомца.", "Choose a project folder for a dedicated pet": "Выберите папку проекта для отдельного питомца", "Add Project": "Добавить проект"
        ]
    ]

    static func localizedText(
        _ english: String,
        language: AppLanguage = AppLanguageSettings.shared.language
    ) -> String {
        additionalTranslations[language]?[english]
            ?? statusTranslations[language]?[english]
            ?? english
    }

    static func text(_ zh: String, _ en: String, _ ja: String? = nil, _ ko: String? = nil) -> String {
        let language = AppLanguageSettings.shared.language
        let translated = localizedText(en, language: language)
        if translated != en { return translated }
        switch language {
        case .simplifiedChinese: return zh
        case .english: return en
        case .japanese: return ja ?? en
        case .korean: return ko ?? en
        default: return en
        }
    }

    static func packName(_ pack: PetPack) -> String {
        switch pack.id {
        case PetPack.catPackID:
            return text("小猫", "Cat")
        case PetPack.bearPackID:
            return text("小熊", "Bear")
        case PetPack.foxPackID:
            return text("小狐狸", "Fox")
        case PetPack.legacyDefaultPackID:
            return text("Orbit", "Orbit")
        default:
            return pack.name
        }
    }

    static func codexAction(_ action: CodexPetTaskAction) -> String {
        switch action {
        case .starting:
            return text("正在启动任务", "Starting task", "タスクを開始中", "작업 시작 중")
        case .thinking:
            return text("正在思考", "Thinking", "思考中", "생각 중")
        case .runningCommand:
            return text("正在运行命令", "Running a command", "コマンドを実行中", "명령 실행 중")
        case .editingFiles:
            return text("正在修改文件", "Editing files", "ファイルを編集中", "파일 수정 중")
        case .readingFiles:
            return text("正在读取文件", "Reading files", "ファイルを読み取り中", "파일 읽는 중")
        case .searchingWeb:
            return text("正在搜索网页", "Searching the web", "ウェブを検索中", "웹 검색 중")
        case .callingTool:
            return text("正在调用工具", "Calling a tool", "ツールを呼び出し中", "도구 호출 중")
        case .waitingForInput:
            return text("正在等待输入", "Waiting for input", "入力を待機中", "입력 대기 중")
        }
    }

    static func growthStage(_ stage: PetGrowthStage) -> String {
        switch stage {
        case .hatchling: return text("初生", "Hatchling", "ハッチリング", "새싹")
        case .companion: return text("伙伴", "Companion", "コンパニオン", "동료")
        case .scout: return text("探索者", "Scout", "スカウト", "스카우트")
        case .hero: return text("英雄", "Hero", "ヒーロー", "히어로")
        case .legend: return text("传说", "Legend", "レジェンド", "전설")
        }
    }

    static func achievement(_ item: DesktopPetAchievement) -> String {
        switch item {
        case .firstSession: return text("第一次完成", "First completion")
        case .sessions10: return text("完成 10 次", "10 completions")
        case .sessions50: return text("完成 50 次", "50 completions")
        case .sessions100: return text("完成 100 次", "100 completions")
        case .tokens1M: return text("100 万 Token", "1M tokens")
        case .tokens10M: return text("1000 万 Token", "10M tokens")
        case .tokens50M: return text("5000 万 Token", "50M tokens")
        case .level5: return text("等级 5", "Level 5")
        case .level10: return text("等级 10", "Level 10")
        case .level20: return text("等级 20", "Level 20")
        case .streak3: return text("连续 3 天", "3-day streak")
        case .streak7: return text("连续 7 天", "7-day streak")
        case .nightOwl: return text("夜间伙伴", "Night owl")
        case .earlyBird: return text("清晨伙伴", "Early bird")
        }
    }

    static func achievementRequirement(_ item: DesktopPetAchievement) -> String {
        switch item {
        case .firstSession: return text("完成 1 个 Agent 会话", "Complete 1 agent session")
        case .sessions10: return text("完成 10 个 Agent 会话", "Complete 10 agent sessions")
        case .sessions50: return text("完成 50 个 Agent 会话", "Complete 50 agent sessions")
        case .sessions100: return text("完成 100 个 Agent 会话", "Complete 100 agent sessions")
        case .tokens1M: return text("累计 100 万 Token", "Use 1M total tokens")
        case .tokens10M: return text("累计 1000 万 Token", "Use 10M total tokens")
        case .tokens50M: return text("累计 5000 万 Token", "Use 50M total tokens")
        case .level5: return text("宠物达到等级 5", "Reach pet level 5")
        case .level10: return text("宠物达到等级 10", "Reach pet level 10")
        case .level20: return text("宠物达到等级 20", "Reach pet level 20")
        case .streak3: return text("连续活跃 3 天", "Be active for 3 days in a row")
        case .streak7: return text("连续活跃 7 天", "Be active for 7 days in a row")
        case .nightOwl: return text("23:00–04:59 有活动", "Be active from 11 PM–4:59 AM")
        case .earlyBird: return text("05:00–07:59 有活动", "Be active from 5–7:59 AM")
        }
    }
}

struct DesktopPetSpriteView: View {
    let pack: PetPack
    let mood: DesktopPetMood
    let size: CGFloat

    var body: some View {
        Group {
            if let image = Self.frameImage(for: pack, mood: mood) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "pawprint.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.25)
                    .foregroundStyle(.cyan)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(PetUI.packName(pack))
    }

    private static var sourceImageCache: [String: NSImage] = [:]
    private static var frameImageCache: [String: NSImage] = [:]

    private static func frameImage(for pack: PetPack, mood: DesktopPetMood) -> NSImage? {
        let key = "\(pack.id)-\(pack.spritePath)-\(pack.columns)-\(mood.rawValue)"
        if let cached = frameImageCache[key] { return cached }
        guard let image = sourceImage(for: pack), image.size.width > 0, image.size.height > 0 else {
            return nil
        }
        let columns = max(pack.columns, 1)
        let frame = pack.frameIndex(for: mood)
        let width = image.size.width / CGFloat(columns)
        let source = NSRect(
            x: min(CGFloat(frame) * width, max(image.size.width - width, 0)),
            y: 0,
            width: width,
            height: image.size.height
        )
        let cropped = NSImage(size: source.size)
        cropped.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: source.size),
            from: source,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        cropped.unlockFocus()
        frameImageCache[key] = cropped
        return cropped
    }

    private static func sourceImage(for pack: PetPack) -> NSImage? {
        let key = "\(pack.id)-\(pack.spritePath)"
        if let cached = sourceImageCache[key] { return cached }
        let url: URL?
        if pack.bundled {
            let resource = (pack.spritePath as NSString).deletingPathExtension
            url = Bundle.main.url(forResource: resource, withExtension: "png", subdirectory: "Pets")
        } else {
            url = URL(fileURLWithPath: pack.spritePath)
        }
        guard let url, let image = NSImage(contentsOf: url) else { return nil }
        sourceImageCache[key] = image
        return image
    }
}

struct DesktopPetFloatingView: View {
    @ObservedObject var store: DesktopPetStore
    let onShowHUD: () -> Void

    @State private var hovering = false
    @State private var isDragging = false
    @State private var showHearts = false

    private var petSize: CGFloat { CGFloat(store.preferences.petSize) }
    private var showsBubble: Bool {
        store.preferences.showMessages && (hovering || store.mood != .idle || !store.activeSessions.isEmpty)
    }

    var body: some View {
        // The speech bubble is an overlay, not a VStack sibling of the pet.
        // Keeping the hit target in a fixed place prevents a mouse-enter event
        // from moving the pet out from under the pointer, which previously
        // caused an enter/exit loop and a visibly flashing bubble.
        ZStack(alignment: .bottom) {
            petBody

            if showsBubble {
                bubbleBody
                    .allowsHitTesting(false)
                    .offset(y: -(petSize + 8))
                    .transition(.scale(scale: 0.88, anchor: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(8)
        .opacity(store.preferences.opacity)
        .animation(.spring(response: 0.3, dampingFraction: 0.68), value: store.mood)
        .animation(.easeInOut(duration: 0.18), value: hovering)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var bubbleBody: some View {
        if store.activeSessions.isEmpty {
            PetSpeechBubble(text: store.speech)
        } else {
            PetAgentActivityBubble(sessions: store.activeSessions)
        }
    }

    private var petBody: some View {
        ZStack(alignment: .topTrailing) {
            DesktopPetSpriteView(
                pack: store.activePack,
                mood: store.mood,
                size: petSize
            )
            if store.mood == .working {
                Image(systemName: "sparkle")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.cyan)
                    .offset(x: 1, y: 4)
                    .transition(.opacity.combined(with: .scale))
            }
            if store.mood == .blocked {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.orange)
                    .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
                    .offset(x: 2, y: 4)
                    .transition(.opacity.combined(with: .scale))
            }
            if showHearts {
                PetHeartBurst()
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale))
            }

            // A native tracking surface keeps the panel movement on the
            // AppKit mouse-event path.  SwiftUI's DragGesture is excellent
            // inside a fixed window, but can feel sticky when it is also
            // responsible for moving that window every frame.
            DesktopPetNativeInteractionSurface(
                onTap: {
                    guard !isDragging else { return }
                    showHearts = true
                    store.feed()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                        showHearts = false
                    }
                },
                onDragStateChanged: { dragging in
                    isDragging = dragging
                },
                onHoverChanged: { hovering = $0 }
            )
            .frame(width: petSize, height: petSize)
        }
        .frame(width: petSize, height: petSize)
        .contentShape(Circle())
        .contextMenu {
            Button(PetUI.text("查看宠物面板", "Show Pet HUD")) {
                onShowHUD()
            }
            Button(PetUI.text("喂一喂", "Feed")) {
                store.feed()
            }
            Divider()
            Button(PetUI.text("隐藏桌面宠物", "Hide Desktop Pet")) {
                store.setEnabled(false)
            }
        }
    }
}

/// A transparent AppKit view that owns a mouse sequence from down to up.  The
/// pointer is measured in screen coordinates, so moving the panel itself never
/// changes the drag baseline and cannot introduce the small back-and-forth jump
/// that a local-coordinate SwiftUI gesture can produce.
private struct DesktopPetNativeInteractionSurface: NSViewRepresentable {
    let onTap: () -> Void
    let onDragStateChanged: (Bool) -> Void
    let onHoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> PetNativeInteractionView {
        let view = PetNativeInteractionView()
        view.onTap = onTap
        view.onDragStateChanged = onDragStateChanged
        view.onHoverChanged = onHoverChanged
        return view
    }

    func updateNSView(_ view: PetNativeInteractionView, context: Context) {
        view.onTap = onTap
        view.onDragStateChanged = onDragStateChanged
        view.onHoverChanged = onHoverChanged
    }
}

private final class PetNativeInteractionView: NSView {
    var onTap: (() -> Void)?
    var onDragStateChanged: ((Bool) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    private var mouseDownPoint: NSPoint?
    private var isDragging = false
    private let dragThreshold: CGFloat = 3
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.openHand.set()
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        guard !isDragging else { return }
        NSCursor.arrow.set()
        onHoverChanged?(false)
    }

    override func cursorUpdate(with event: NSEvent) {
        (isDragging ? NSCursor.closedHand : NSCursor.openHand).set()
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = screenPoint(for: event)
        isDragging = false
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downPoint = mouseDownPoint else { return }
        let currentPoint = screenPoint(for: event)
        if !isDragging {
            let deltaX = currentPoint.x - downPoint.x
            let deltaY = currentPoint.y - downPoint.y
            guard hypot(deltaX, deltaY) >= dragThreshold else { return }
            isDragging = true
            NSCursor.closedHand.set()
            onDragStateChanged?(true)
            DesktopPetWindowController.shared.beginDrag(at: downPoint)
        }
        DesktopPetWindowController.shared.updateDrag(to: currentPoint)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownPoint = nil
            if isDragging {
                isDragging = false
                onDragStateChanged?(false)
            }
            NSCursor.openHand.set()
        }
        if isDragging {
            DesktopPetWindowController.shared.endDrag()
        } else {
            onTap?()
        }
    }

    private func screenPoint(for event: NSEvent) -> NSPoint {
        if let window {
            return window.convertPoint(toScreen: event.locationInWindow)
        }
        return NSEvent.mouseLocation
    }
}

private struct PetHeartBurst: View {
    var body: some View {
        ZStack {
            Image(systemName: "heart.fill")
                .foregroundStyle(.pink)
                .offset(x: -18, y: -18)
            Image(systemName: "heart.fill")
                .foregroundStyle(.purple)
                .font(.system(size: 10))
                .offset(x: 15, y: -26)
            Image(systemName: "sparkles")
                .foregroundStyle(.yellow)
                .font(.system(size: 11))
                .offset(x: 2, y: -40)
        }
        .font(.system(size: 13))
    }
}

private struct PetSpeechBubble: View {
    let text: String

    var body: some View {
        VStack(spacing: -1) {
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 200)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
            Triangle()
                .fill(Color.white.opacity(0.42))
                .frame(width: 12, height: 7)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PetAgentActivityBubble: View {
    let sessions: [PetActiveAgentSession]

    private var displayedSessions: [PetActiveAgentSession] {
        sessions.sorted {
            if $0.mood != $1.mood { return Self.priority(for: $0.mood) < Self.priority(for: $1.mood) }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private static func priority(for mood: DesktopPetMood) -> Int {
        switch mood {
        case .blocked: return 0
        case .waiting: return 1
        case .working: return 2
        case .celebrating, .resting, .idle: return 3
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(displayedSessions.prefix(3))) { session in
                PetAgentSessionRow(session: session, compact: true)
            }
            if sessions.count > 3 {
                Text("+\(sessions.count - 3) \(PetUI.text("个 Agent", "more agents"))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 240, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 7, y: 3)
    }
}

private struct PetAgentSessionRow: View {
    let session: PetActiveAgentSession
    var compact = false

    private var stateColor: Color {
        switch session.mood {
        case .blocked: return .red
        case .waiting: return .orange
        case .working: return .cyan
        case .celebrating, .resting, .idle: return .secondary
        }
    }

    private var stateTitle: String {
        switch session.mood {
        case .blocked: return PetUI.text("受阻", "Blocked")
        case .waiting: return PetUI.text("等待", "Waiting")
        case .working: return PetUI.text("工作中", "Working")
        case .celebrating, .resting, .idle: return PetUI.text("空闲", "Idle")
        }
    }

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { timeline in
            HStack(spacing: 6) {
                if let provider = session.provider {
                    ProviderLogo(
                        provider: provider,
                        size: compact ? 14 : 17,
                        fallbackColor: ProviderPalette.color(for: provider)
                    )
                } else {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: compact ? 10 : 12, weight: .semibold))
                        .foregroundStyle(stateColor)
                        .frame(width: compact ? 14 : 17, height: compact ? 14 : 17)
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(stateColor)
                            .frame(width: 5, height: 5)
                        Text(stateTitle)
                            .font(.system(size: compact ? 10 : 11, weight: .bold, design: .rounded))
                        if let model = session.model, !model.isEmpty {
                            Text(model)
                                .font(.system(size: compact ? 8 : 9, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(stateColor.opacity(0.16), in: Capsule())
                        }
                    }
                    if let message = session.message, !message.isEmpty {
                        Text(message)
                            .font(.system(size: compact ? 10 : 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let projectPath = session.projectPath {
                        Text(URL(fileURLWithPath: projectPath).lastPathComponent)
                            .font(.system(size: compact ? 10 : 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 2)
                Text(Self.elapsed(since: session.stateSince, now: timeline.date))
                    .font(.system(size: compact ? 9 : 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static func elapsed(since date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes < 60 {
            return "\(minutes)m \(String(format: "%02d", remainingSeconds))s"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return "\(hours)h \(String(format: "%02d", remainingMinutes))m \(String(format: "%02d", remainingSeconds))s"
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct DesktopPetHUDView: View {
    @ObservedObject var store: DesktopPetStore
    @ObservedObject private var languageSettings = AppLanguageSettings.shared
    let onOpenSettings: () -> Void
    @State private var showsAchievementDetails = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider()
                care
                if !store.activeSessions.isEmpty {
                    activeAgents
                }
                history
                if !store.quotaRows.isEmpty {
                    liveQuotas
                }
                achievements
                footer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .frame(maxHeight: 560)
        .frame(width: 330)
        .background(.ultraThinMaterial)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 11) {
            DesktopPetSpriteView(pack: store.activePack, mood: store.mood, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.activePack.name)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("\(PetUI.growthStage(store.progress.stage)) · \(PetUI.text("等级", "Level")) \(store.progress.level)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(store.progress.totalXP) XP")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan)
        }
    }

    private var care: some View {
        VStack(alignment: .leading, spacing: 9) {
            PetHUDMetric(
                icon: "sparkles",
                label: PetUI.text("成长进度", "Growth"),
                value: "\(store.progress.xpIntoCurrentLevel) / \(store.progress.xpForNextLevel) XP",
                progress: store.nextLevelProgress,
                color: .cyan
            )
            PetHUDMetric(
                icon: "bolt.heart.fill",
                label: PetUI.text("能量", "Energy"),
                value: "\(store.energyPercent)%",
                progress: Double(store.energyPercent) / 100,
                color: .pink
            )
            HStack(spacing: 10) {
                Label("\(store.progress.dailyStreak)", systemImage: "flame.fill")
                    .foregroundStyle(.orange)
                Text(PetUI.text("连续活跃天数", "active-day streak"))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(store.progress.completedSessions)")
                    .fontWeight(.bold)
                Text(PetUI.text("完成", "completed"))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(PetUI.text("最近 7 天活跃度", "Seven-day activity"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 7) {
                let maximum = max(store.recentHistory.map(\.tokens).max() ?? 0, 1)
                ForEach(store.recentHistory) { day in
                    VStack(spacing: 4) {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.cyan.opacity(0.95), .blue.opacity(0.55)],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: 22, height: max(4, 38 * day.tokens / maximum))
                        Text(dayFormatter.string(from: day.day))
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
            .frame(height: 59)
        }
    }

    private var activeAgents: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(PetUI.text("正在运行的 Agent", "Active agents"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(store.activeSessions.count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
            }
            ForEach(store.activeSessions.sorted(by: { $0.updatedAt > $1.updatedAt })) { session in
                PetAgentSessionRow(session: session)
            }
        }
    }

    private var achievements: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showsAchievementDetails.toggle()
                }
            } label: {
                HStack {
                    Label(
                        "\(store.achievements.count) / \(DesktopPetAchievement.allCases.count)",
                        systemImage: "medal.fill"
                    )
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.yellow)
                    Text(PetUI.text("成就", "Achievements"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(PetUI.text(showsAchievementDetails ? "收起" : "查看全部", showsAchievementDetails ? "Hide" : "View all"))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.cyan)
                    Image(systemName: showsAchievementDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsAchievementDetails {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)],
                    alignment: .leading,
                    spacing: 7
                ) {
                    ForEach(DesktopPetAchievement.allCases) { achievement in
                        PetAchievementTile(
                            achievement: achievement,
                            isUnlocked: store.achievements.contains(achievement)
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var liveQuotas: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(PetUI.text("实时额度", "Live quotas"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(store.quotaRows) { row in
                HStack(spacing: 6) {
                    ProviderLogo(
                        provider: row.provider,
                        size: 15,
                        fallbackColor: ProviderPalette.color(for: row.provider)
                    )
                    Text(L10n.providerName(row.provider))
                        .lineLimit(1)
                    Text(row.window.title)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text("\(row.remainingPercent)%")
                        .fontWeight(.bold)
                    if let resetAt = row.resetAt {
                        Text(
                            L10n.relativeDateString(
                                resetAt,
                                language: languageSettings.language
                            )
                        )
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                store.feed()
            } label: {
                Label(PetUI.text("喂一喂", "Feed"), systemImage: "heart.fill")
            }
            .buttonStyle(.borderedProminent)
            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.bordered)
            Spacer()
            Button(PetUI.text("隐藏", "Hide")) {
                store.setEnabled(false)
            }
            .buttonStyle(.link)
        }
    }

    private var dayFormatter: DateFormatter {
        L10n.weekdayFormatter(language: languageSettings.language)
    }
}

private struct PetAchievementTile: View {
    let achievement: DesktopPetAchievement
    let isUnlocked: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: isUnlocked ? "checkmark.seal.fill" : "lock.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isUnlocked ? Color.yellow : Color.secondary.opacity(0.8))
                .frame(width: 15, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(PetUI.achievement(achievement))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(PetUI.achievementRequirement(achievement))
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 45, alignment: .leading)
        .background(
            isUnlocked ? Color.yellow.opacity(0.10) : Color.primary.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isUnlocked ? Color.yellow.opacity(0.20) : Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityLabel("\(PetUI.achievement(achievement)) · \(PetUI.achievementRequirement(achievement))")
    }
}

private struct PetHUDMetric: View {
    let icon: String
    let label: String
    let value: String
    let progress: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 15)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
            }
            ProgressView(value: min(max(progress, 0), 1))
                .tint(color)
        }
    }
}
