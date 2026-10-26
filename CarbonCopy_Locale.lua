--
-- CarbonCopy_Locale.lua
-- Every text CarbonCopy shows (players, GMs, console) and the mails it sends, organised by locale.
--
-- Locale IDs come from player:GetDbcLocale() (mails: the copying player / the target account's locale):
--   0=enUS, 1=koKR, 2=frFR, 3=deDE, 4=zhCN, 5=zhTW, 6=esES, 7=esMX, 8=ruRU
--
-- Every key is a table {[locale_id] = "translated string", ...}, or a plain string used for every locale.
-- The [0] (enUS) entry is the fallback used whenever no translation exists for a locale.
-- Use %d / %s for dynamic values. Lua can't reorder them: keep them in the same order as the English text.
-- Server log lines and the reasons written to the log tables are always English and stay in CarbonCopy.lua.
--

local L = {}

-- ---------------------------------------------------------------------------
-- .carboncopy (no arguments): balance, how to use it, eligibility and ticket costs
-- ---------------------------------------------------------------------------
L.TICKETS = {
    [0] = "You currently have %d tickets available for CarbonCopy.",
    [1] = "현재 CarbonCopy 티켓이 %d개 있습니다.",
    [2] = "Vous disposez actuellement de %d tickets CarbonCopy.",
    [3] = "Du hast derzeit %d CarbonCopy-Tickets.",
    [4] = "你当前拥有 %d 张 CarbonCopy 票券。",
    [5] = "你目前擁有 %d 張 CarbonCopy 票券。",
    [6] = "Actualmente tienes %d tickets de CarbonCopy.",
    [7] = "Actualmente tienes %d tickets de CarbonCopy.",
    [8] = "У вас %d жетонов CarbonCopy.",
}

L.USAGE = {
    [0] = "To copy this character: create a new character of the same race and class on this account (do NOT log it in), then type .carboncopy NewCharacterName while logged in on this character. You will be prompted when you can log in.",
    [1] = "이 캐릭터를 복사하려면: 같은 계정에 같은 종족과 직업의 새 캐릭터를 만드세요 (접속하지 마세요). 그다음 이 캐릭터로 접속한 상태에서 .carboncopy 새캐릭터이름 을 입력하세요. 접속해도 될 때 안내 메시지가 표시됩니다.",
    [2] = "Pour copier ce personnage : créez un nouveau personnage de même race et classe sur ce compte (ne vous connectez PAS avec), puis tapez .carboncopy NomDuNouveauPersonnage en étant connecté sur ce personnage. Un message vous indiquera quand vous pourrez vous connecter.",
    [3] = "So kopierst du diesen Charakter: Erstelle auf diesem Account einen neuen Charakter mit gleicher Rasse und Klasse (NICHT einloggen), dann tippe .carboncopy NeuerCharakterName, während du mit diesem Charakter eingeloggt bist. Du wirst benachrichtigt, sobald du dich einloggen kannst.",
    [4] = "复制此角色：在本账号创建一个相同种族和职业的新角色（不要登录它），然后在此角色登录时输入 .carboncopy 新角色名。可以登录时会提示你。",
    [5] = "複製此角色：在本帳號建立一個相同種族和職業的新角色（不要登入它），然後在此角色登入時輸入 .carboncopy 新角色名稱。可以登入時會提示你。",
    [6] = "Para copiar este personaje: crea un personaje nuevo de la misma raza y clase en esta cuenta (NO entres con él) y escribe .carboncopy NombreNuevoPersonaje mientras estás conectado con este personaje. Se te avisará cuando puedas conectarte.",
    [7] = "Para copiar este personaje: crea un personaje nuevo de la misma raza y clase en esta cuenta (NO entres con él) y escribe .carboncopy NombreNuevoPersonaje mientras estás conectado con este personaje. Se te avisará cuando puedas conectarte.",
    [8] = "Чтобы скопировать этого персонажа: создайте на этом аккаунте нового персонажа той же расы и класса (НЕ заходите им), затем введите .carboncopy ИмяНовогоПерсонажа, находясь в игре этим персонажем. Вам сообщат, когда можно будет войти.",
}

L.ELIGIBLE = {
    [0] = "This character (level %d) can be copied for %d ticket(s).",
    [1] = "이 캐릭터(레벨 %d)는 티켓 %d개로 복사할 수 있습니다.",
    [2] = "Ce personnage (niveau %d) peut être copié pour %d ticket(s).",
    [3] = "Dieser Charakter (Stufe %d) kann für %d Ticket(s) kopiert werden.",
    [4] = "此角色（%d 级）可以用 %d 张票券复制。",
    [5] = "此角色（%d 級）可以用 %d 張票券複製。",
    [6] = "Este personaje (nivel %d) se puede copiar por %d ticket(s).",
    [7] = "Este personaje (nivel %d) se puede copiar por %d ticket(s).",
    [8] = "Этого персонажа (уровень %d) можно скопировать за %d жетон(ов).",
}

L.NOT_ENOUGH_TICKETS = {
    [0] = "This character (level %d) needs %d ticket(s) to be copied, but you only have %d.",
    [1] = "이 캐릭터(레벨 %d)를 복사하려면 티켓 %d개가 필요하지만 %d개만 있습니다.",
    [2] = "Ce personnage (niveau %d) nécessite %d ticket(s) pour être copié, mais vous n'en avez que %d.",
    [3] = "Dieser Charakter (Stufe %d) braucht %d Ticket(s) zum Kopieren, du hast aber nur %d.",
    [4] = "复制此角色（%d 级）需要 %d 张票券，但你只有 %d 张。",
    [5] = "複製此角色（%d 級）需要 %d 張票券，但你只有 %d 張。",
    [6] = "Este personaje (nivel %d) necesita %d ticket(s) para copiarse, pero solo tienes %d.",
    [7] = "Este personaje (nivel %d) necesita %d ticket(s) para copiarse, pero solo tienes %d.",
    [8] = "Для копирования этого персонажа (уровень %d) нужно %d жетон(ов), а у вас только %d.",
}

L.LEVEL_TOO_HIGH = {
    [0] = "This character can't be copied: level %d is above the maximum level %d.",
    [1] = "이 캐릭터는 복사할 수 없습니다: 레벨 %d은(는) 최대 레벨 %d보다 높습니다.",
    [2] = "Ce personnage ne peut pas être copié : le niveau %d dépasse le niveau maximum %d.",
    [3] = "Dieser Charakter kann nicht kopiert werden: Stufe %d liegt über der Höchststufe %d.",
    [4] = "此角色无法复制：%d 级超过了最高等级 %d。",
    [5] = "此角色無法複製：%d 級超過了最高等級 %d。",
    [6] = "Este personaje no se puede copiar: el nivel %d supera el nivel máximo %d.",
    [7] = "Este personaje no se puede copiar: el nivel %d supera el nivel máximo %d.",
    [8] = "Этого персонажа нельзя скопировать: уровень %d выше максимального уровня %d.",
}

L.WRONG_MAP = {
    [0] = "You can only copy outside of dungeons, raids, battlegrounds and arenas.",
    [1] = "던전, 공격대, 전장, 투기장 밖에서만 복사할 수 있습니다.",
    [2] = "Vous ne pouvez copier qu'en dehors des donjons, raids, champs de bataille et arènes.",
    [3] = "Kopieren ist nur außerhalb von Dungeons, Schlachtzügen, Schlachtfeldern und Arenen möglich.",
    [4] = "只能在地下城、团队副本、战场和竞技场之外复制。",
    [5] = "只能在地城、團隊副本、戰場和競技場之外複製。",
    [6] = "Solo puedes copiar fuera de mazmorras, bandas, campos de batalla y arenas.",
    [7] = "Solo puedes copiar fuera de mazmorras, bandas, campos de batalla y arenas.",
    [8] = "Копировать можно только вне подземелий, рейдов, полей боя и арен.",
}

L.COSTS_HEADER = {
    [0] = "Ticket costs:",
    [1] = "티켓 비용:",
    [2] = "Coût en tickets :",
    [3] = "Ticketkosten:",
    [4] = "票券花费：",
    [5] = "票券花費：",
    [6] = "Coste en tickets:",
    [7] = "Costo en tickets:",
    [8] = "Стоимость в жетонах:",
}

L.COST_RANGE = {
    [0] = "  Level %d - %d = %d ticket(s)",
    [1] = "  레벨 %d - %d = 티켓 %d개",
    [2] = "  Niveau %d - %d = %d ticket(s)",
    [3] = "  Stufe %d - %d = %d Ticket(s)",
    [4] = "  %d - %d 级 = %d 张票券",
    [5] = "  %d - %d 級 = %d 張票券",
    [6] = "  Nivel %d - %d = %d ticket(s)",
    [7] = "  Nivel %d - %d = %d ticket(s)",
    [8] = "  Уровень %d - %d = %d жетон(ов)",
}

L.COST_LEVEL = {
    [0] = "  Level %d = %d ticket(s)",
    [1] = "  레벨 %d = 티켓 %d개",
    [2] = "  Niveau %d = %d ticket(s)",
    [3] = "  Stufe %d = %d Ticket(s)",
    [4] = "  %d 级 = %d 张票券",
    [5] = "  %d 級 = %d 張票券",
    [6] = "  Nivel %d = %d ticket(s)",
    [7] = "  Nivel %d = %d ticket(s)",
    [8] = "  Уровень %d = %d жетон(ов)",
}

L.COST_SINGLE = {
    [0] = "  Every copy = 1 ticket",
    [1] = "  복사 1회 = 티켓 1개",
    [2] = "  Chaque copie = 1 ticket",
    [3] = "  Jede Kopie = 1 Ticket",
    [4] = "  每次复制 = 1 张票券",
    [5] = "  每次複製 = 1 張票券",
    [6] = "  Cada copia = 1 ticket",
    [7] = "  Cada copia = 1 ticket",
    [8] = "  Каждое копирование = 1 жетон",
}

L.STARTER_TICKETS = {
    [0] = "Starter tickets = %d",
    [1] = "기본 지급 티켓 = %d",
    [2] = "Tickets de départ = %d",
    [3] = "Starttickets = %d",
    [4] = "初始票券 = %d",
    [5] = "初始票券 = %d",
    [6] = "Tickets iniciales = %d",
    [7] = "Tickets iniciales = %d",
    [8] = "Стартовые жетоны = %d",
}

-- ---------------------------------------------------------------------------
-- General
-- ---------------------------------------------------------------------------
L.ERR_NO_PERMISSION = {
    [0] = "You lack permissions to execute this command.",
    [1] = "이 명령을 실행할 권한이 없습니다.",
    [2] = "Vous n'avez pas la permission d'exécuter cette commande.",
    [3] = "Dir fehlt die Berechtigung, diesen Befehl auszuführen.",
    [4] = "你没有执行此命令的权限。",
    [5] = "你沒有執行此指令的權限。",
    [6] = "No tienes permiso para ejecutar este comando.",
    [7] = "No tienes permiso para ejecutar este comando.",
    [8] = "У вас нет прав на выполнение этой команды.",
}

L.ERR_SERVER_BUSY = {
    [0] = "The server is currently busy. Please try again in a few seconds.",
    [1] = "서버가 현재 사용 중입니다. 몇 초 후에 다시 시도하세요.",
    [2] = "Le serveur est actuellement occupé. Réessayez dans quelques secondes.",
    [3] = "Der Server ist gerade beschäftigt. Bitte versuche es in ein paar Sekunden erneut.",
    [4] = "服务器当前繁忙，请几秒后再试。",
    [5] = "伺服器目前忙碌中，請幾秒後再試。",
    [6] = "El servidor está ocupado. Inténtalo de nuevo en unos segundos.",
    [7] = "El servidor está ocupado. Inténtalo de nuevo en unos segundos.",
    [8] = "Сервер сейчас занят. Попробуйте снова через несколько секунд.",
}

-- ---------------------------------------------------------------------------
-- .carboncopy NewCharacterName (player)
-- ---------------------------------------------------------------------------
L.ERR_COPY_FROM_CONSOLE = {
    [0] = "This command can not be run from the console, but only from the character to copy.",
}

-- %d = max level
L.ERR_COPY_LEVEL_TOO_HIGH = {
    [0] = "The character you want to copy from is too high level. Max level is %d. Aborting.",
    [1] = "복사하려는 캐릭터의 레벨이 너무 높습니다. 최대 레벨은 %d입니다. 중단합니다.",
    [2] = "Le personnage à copier a un niveau trop élevé. Le niveau maximum est %d. Abandon.",
    [3] = "Der zu kopierende Charakter hat eine zu hohe Stufe. Maximale Stufe ist %d. Abbruch.",
    [4] = "要复制的角色等级过高。最高等级为 %d。已中止。",
    [5] = "要複製的角色等級過高。最高等級為 %d。已中止。",
    [6] = "El personaje que quieres copiar tiene un nivel demasiado alto. El nivel máximo es %d. Cancelado.",
    [7] = "El personaje que quieres copiar tiene un nivel demasiado alto. El nivel máximo es %d. Cancelado.",
    [8] = "Уровень копируемого персонажа слишком высок. Максимальный уровень: %d. Отмена.",
}

L.ERR_COPY_NAME_NOT_FOUND = {
    [0] = "Name not found. Check spelling. Aborting.",
    [1] = "이름을 찾을 수 없습니다. 철자를 확인하세요. 중단합니다.",
    [2] = "Nom introuvable. Vérifiez l'orthographe. Abandon.",
    [3] = "Name nicht gefunden. Prüfe die Schreibweise. Abbruch.",
    [4] = "未找到该名字，请检查拼写。已中止。",
    [5] = "找不到該名字，請檢查拼字。已中止。",
    [6] = "Nombre no encontrado. Revisa la ortografía. Cancelado.",
    [7] = "Nombre no encontrado. Revisa la ortografía. Cancelado.",
    [8] = "Имя не найдено. Проверьте написание. Отмена.",
}

L.ERR_COPY_NOT_SAME_ACCOUNT = {
    [0] = "The requested character is not on the same account. Aborting.",
    [1] = "요청한 캐릭터가 같은 계정에 없습니다. 중단합니다.",
    [2] = "Le personnage demandé n'est pas sur le même compte. Abandon.",
    [3] = "Der angegebene Charakter ist nicht auf demselben Account. Abbruch.",
    [4] = "目标角色不在同一账号中。已中止。",
    [5] = "目標角色不在同一帳號中。已中止。",
    [6] = "El personaje indicado no está en la misma cuenta. Cancelado.",
    [7] = "El personaje indicado no está en la misma cuenta. Cancelado.",
    [8] = "Указанный персонаж находится на другой учётной записи. Отмена.",
}

L.ERR_COPY_NOT_ENOUGH_TICKETS = {
    [0] = "You do not have enough Carbon Copy tickets to execute this command. Aborting.",
    [1] = "이 명령을 실행할 Carbon Copy 티켓이 부족합니다. 중단합니다.",
    [2] = "Vous n'avez pas assez de tickets Carbon Copy pour cette commande. Abandon.",
    [3] = "Du hast nicht genug Carbon-Copy-Tickets für diesen Befehl. Abbruch.",
    [4] = "你的 Carbon Copy 票券不足，无法执行此命令。已中止。",
    [5] = "你的 Carbon Copy 票券不足，無法執行此指令。已中止。",
    [6] = "No tienes suficientes tickets de Carbon Copy para este comando. Cancelado.",
    [7] = "No tienes suficientes tickets de Carbon Copy para este comando. Cancelado.",
    [8] = "Недостаточно жетонов Carbon Copy для этой команды. Отмена.",
}

L.ERR_COPY_NOT_SAME_RACE = {
    [0] = "The requested character is not the same race as this character. Aborting.",
    [1] = "요청한 캐릭터의 종족이 이 캐릭터와 다릅니다. 중단합니다.",
    [2] = "Le personnage demandé n'est pas de la même race que ce personnage. Abandon.",
    [3] = "Der angegebene Charakter hat nicht dasselbe Volk wie dieser Charakter. Abbruch.",
    [4] = "目标角色与当前角色种族不同。已中止。",
    [5] = "目標角色與目前角色種族不同。已中止。",
    [6] = "El personaje indicado no es de la misma raza que este personaje. Cancelado.",
    [7] = "El personaje indicado no es de la misma raza que este personaje. Cancelado.",
    [8] = "Указанный персонаж другой расы. Отмена.",
}

L.ERR_COPY_NOT_SAME_CLASS = {
    [0] = "The requested character is not the same class as this character. Aborting.",
    [1] = "요청한 캐릭터의 직업이 이 캐릭터와 다릅니다. 중단합니다.",
    [2] = "Le personnage demandé n'est pas de la même classe que ce personnage. Abandon.",
    [3] = "Der angegebene Charakter hat nicht dieselbe Klasse wie dieser Charakter. Abbruch.",
    [4] = "目标角色与当前角色职业不同。已中止。",
    [5] = "目標角色與目前角色職業不同。已中止。",
    [6] = "El personaje indicado no es de la misma clase que este personaje. Cancelado.",
    [7] = "El personaje indicado no es de la misma clase que este personaje. Cancelado.",
    [8] = "Указанный персонаж другого класса. Отмена.",
}

L.ERR_COPY_ALREADY_LOGGED_IN = {
    [0] = "The requested character has been logged in already (or has already been Carbon Copied). Aborting.",
    [1] = "요청한 캐릭터는 이미 접속한 적이 있습니다 (또는 이미 Carbon Copy 되었습니다). 중단합니다.",
    [2] = "Le personnage demandé s'est déjà connecté (ou a déjà été copié). Abandon.",
    [3] = "Der angegebene Charakter war bereits eingeloggt (oder wurde bereits kopiert). Abbruch.",
    [4] = "目标角色已经登录过（或已经被复制过）。已中止。",
    [5] = "目標角色已經登入過（或已經被複製過）。已中止。",
    [6] = "El personaje indicado ya se ha conectado (o ya ha sido copiado). Cancelado.",
    [7] = "El personaje indicado ya se ha conectado (o ya ha sido copiado). Cancelado.",
    [8] = "Указанный персонаж уже входил в игру (или уже был скопирован). Отмена.",
}

L.ERR_COPY_WRONG_MAP = {
    [0] = "You are not in an allowed map. Try again outside/not in a dungeon.",
    [1] = "허용된 지역이 아닙니다. 던전 밖에서 다시 시도하세요.",
    [2] = "Vous n'êtes pas sur une carte autorisée. Réessayez à l'extérieur, hors d'un donjon.",
    [3] = "Du bist auf keiner erlaubten Karte. Versuche es draußen, nicht in einem Dungeon.",
    [4] = "你不在允许的地图中。请在副本外再试。",
    [5] = "你不在允許的地圖中。請在副本外再試。",
    [6] = "No estás en un mapa permitido. Inténtalo fuera, no en una mazmorra.",
    [7] = "No estás en un mapa permitido. Inténtalo fuera, no en un calabozo.",
    [8] = "Вы находитесь на недопустимой карте. Попробуйте снова вне подземелья.",
}

-- %d = tickets charged, %d = tickets left
L.COPY_STARTED = {
    [0] = "Copy started. You have been charged %d ticket(s) for this action. There are %d ticket(s) left.",
    [1] = "복사를 시작했습니다. 티켓 %d개가 차감되었습니다. 남은 티켓: %d개.",
    [2] = "Copie lancée. %d ticket(s) ont été débités. Il vous reste %d ticket(s).",
    [3] = "Kopie gestartet. Dir wurden %d Ticket(s) berechnet. Verbleibend: %d Ticket(s).",
    [4] = "复制已开始。已扣除 %d 张票券，剩余 %d 张。",
    [5] = "複製已開始。已扣除 %d 張票券，剩餘 %d 張。",
    [6] = "Copia iniciada. Se te han cobrado %d ticket(s). Te quedan %d ticket(s).",
    [7] = "Copia iniciada. Se te han cobrado %d ticket(s). Te quedan %d ticket(s).",
    [8] = "Копирование начато. Списано жетонов: %d. Осталось: %d.",
}

-- Shown when a copy starts. [0] (English) and COPY_STAY_ITALIAN are always shown, plus the player's own locale.
L.COPY_STAY = {
    [0] = "STAY logged in for one minute!",
    [1] = "1분 동안 접속 상태를 유지하세요!",
    [2] = "RESTEZ connecte pendant une minute!",
    [3] = "BLEIB eingeloggt für eine Minute!",
    [4] = "请保持在线一分钟！",
    [5] = "請保持在線一分鐘！",
    [6] = "MANTENTE conectado por un minuto!",
    [7] = "MANTENTE conectado por un minuto!",
    [8] = "ОСТАВАЙТЕСЬ В ИГРЕ ОДНУ МИНУТУ!",
}

-- Italian has no client locale in Wrath, so it is always shown
L.COPY_STAY_ITALIAN = "RIMANI connesso per un minuto!"

-- %s = new character name
L.COPY_COMPLETE = {
    [0] = "Character copy complete! %s has been copied. You can log out now.",
    [1] = "캐릭터 복사 완료! %s 캐릭터가 복사되었습니다. 이제 접속을 종료해도 됩니다.",
    [2] = "Copie terminée ! %s a été copié. Vous pouvez vous déconnecter.",
    [3] = "Kopie abgeschlossen! %s wurde kopiert. Du kannst dich jetzt ausloggen.",
    [4] = "角色复制完成！%s 已复制完毕。你现在可以下线了。",
    [5] = "角色複製完成！%s 已複製完畢。你現在可以登出了。",
    [6] = "¡Copia completada! %s ha sido copiado. Ya puedes desconectarte.",
    [7] = "¡Copia completada! %s ha sido copiado. Ya puedes desconectarte.",
    [8] = "Копирование завершено! Персонаж %s скопирован. Теперь можно выйти из игры.",
}

-- %d = tickets refunded
L.COPY_FAILED_REFUNDED = {
    [0] = "Something went wrong during the copy. Your %d ticket(s) have been refunded and you can try again.",
    [1] = "복사 중 문제가 발생했습니다. 티켓 %d개가 환불되었으며 다시 시도할 수 있습니다.",
    [2] = "Un problème est survenu pendant la copie. Vos %d ticket(s) ont été remboursés, vous pouvez réessayer.",
    [3] = "Bei der Kopie ist etwas schiefgelaufen. Deine %d Ticket(s) wurden erstattet, du kannst es erneut versuchen.",
    [4] = "复制过程中出现问题。已退还你的 %d 张票券，你可以再试一次。",
    [5] = "複製過程中出現問題。已退還你的 %d 張票券，你可以再試一次。",
    [6] = "Algo salió mal durante la copia. Se te han devuelto %d ticket(s) y puedes intentarlo de nuevo.",
    [7] = "Algo salió mal durante la copia. Se te han devuelto %d ticket(s) y puedes intentarlo de nuevo.",
    [8] = "Во время копирования произошла ошибка. Жетоны возвращены (%d), можно попробовать снова.",
}

L.COPY_FAILED_CONTACT_GM = {
    [0] = "Something went wrong while finishing the copy. Your items were mailed; please contact a Game Master.",
    [1] = "복사를 마무리하는 중 문제가 발생했습니다. 아이템은 우편으로 발송되었습니다. 게임 마스터에게 문의하세요.",
    [2] = "Un problème est survenu à la fin de la copie. Vos objets ont été envoyés ; contactez un maître de jeu.",
    [3] = "Beim Abschluss der Kopie ist etwas schiefgelaufen. Deine Gegenstände wurden verschickt; bitte wende dich an einen Spielleiter.",
    [4] = "完成复制时出现问题。你的物品已邮寄，请联系游戏管理员。",
    [5] = "完成複製時出現問題。你的物品已郵寄，請聯絡遊戲管理員。",
    [6] = "Algo salió mal al terminar la copia. Tus objetos se han enviado; contacta con un Maestro de Juego.",
    [7] = "Algo salió mal al terminar la copia. Tus objetos se han enviado; contacta a un Maestro de Juego.",
    [8] = "При завершении копирования произошла ошибка. Предметы отправлены, обратитесь к гейм-мастеру.",
}

-- ---------------------------------------------------------------------------
-- Mails. Copy mails use the copying player's locale, restore mails the target account's locale.
-- Bodies: first %s = character name, second %s = Config.mailSignature
-- ---------------------------------------------------------------------------
L.MAIL_GEAR_SUBJECT = {
    [0] = "Copied items",
    [1] = "복사된 아이템",
    [2] = "Objets copiés",
    [3] = "Kopierte Gegenstände",
    [4] = "复制的物品",
    [5] = "複製的物品",
    [6] = "Objetos copiados",
    [7] = "Objetos copiados",
    [8] = "Скопированные предметы",
}

L.MAIL_GEAR_BODY = {
    [0] = "Hello %s,\n \n here is your gear. Have fun with the new twink!\n \n- Sincerely,\n %s",
    [1] = "%s 님, 안녕하세요.\n \n 장비를 보내드립니다. 새 캐릭터와 즐거운 시간 보내세요!\n \n- 감사합니다.\n %s",
    [2] = "Bonjour %s,\n \n voici votre équipement. Amusez-vous bien avec votre nouveau personnage !\n \n- Cordialement,\n %s",
    [3] = "Hallo %s,\n \n hier ist deine Ausrüstung. Viel Spaß mit deinem neuen Twink!\n \n- Mit freundlichen Grüßen,\n %s",
    [4] = "%s 你好，\n \n 这是你的装备。祝你在新角色上玩得开心！\n \n- 此致，\n %s",
    [5] = "%s 你好，\n \n 這是你的裝備。祝你在新角色上玩得開心！\n \n- 敬上，\n %s",
    [6] = "Hola %s,\n \n aquí tienes tu equipo. ¡Diviértete con tu nuevo personaje!\n \n- Atentamente,\n %s",
    [7] = "Hola %s,\n \n aquí tienes tu equipo. ¡Diviértete con tu nuevo personaje!\n \n- Atentamente,\n %s",
    [8] = "Здравствуйте, %s!\n \n Вот ваше снаряжение. Удачи с новым персонажем!\n \n- С уважением,\n %s",
}

L.MAIL_TOTEMS_SUBJECT = {
    [0] = "Copied totems",
    [1] = "복사된 토템",
    [2] = "Totems copiés",
    [3] = "Kopierte Totems",
    [4] = "复制的图腾",
    [5] = "複製的圖騰",
    [6] = "Tótems copiados",
    [7] = "Tótems copiados",
    [8] = "Скопированные тотемы",
}

L.MAIL_TOTEMS_BODY = {
    [0] = "Hello %s,\n \n here are your shaman totems. Keep them in your bags so you can use your totem spells!\n \n- Sincerely,\n %s",
    [1] = "%s 님, 안녕하세요.\n \n 주술사 토템을 보내드립니다. 토템 주문을 사용하려면 가방에 보관하세요!\n \n- 감사합니다.\n %s",
    [2] = "Bonjour %s,\n \n voici vos totems de chaman. Gardez-les dans vos sacs pour pouvoir lancer vos sorts de totem !\n \n- Cordialement,\n %s",
    [3] = "Hallo %s,\n \n hier sind deine Schamanentotems. Behalte sie in deinen Taschen, damit du deine Totemzauber wirken kannst!\n \n- Mit freundlichen Grüßen,\n %s",
    [4] = "%s 你好，\n \n 这是你的萨满图腾。请把它们放在背包里，这样才能施放图腾法术！\n \n- 此致，\n %s",
    [5] = "%s 你好，\n \n 這是你的薩滿圖騰。請把它們放在背包裡，這樣才能施放圖騰法術！\n \n- 敬上，\n %s",
    [6] = "Hola %s,\n \n aquí tienes tus tótems de chamán. ¡Guárdalos en tus bolsas para poder usar tus hechizos de tótem!\n \n- Atentamente,\n %s",
    [7] = "Hola %s,\n \n aquí tienes tus tótems de chamán. ¡Guárdalos en tus bolsas para poder usar tus hechizos de tótem!\n \n- Atentamente,\n %s",
    [8] = "Здравствуйте, %s!\n \n Вот ваши тотемы шамана. Держите их в сумках, чтобы использовать заклинания тотемов!\n \n- С уважением,\n %s",
}

L.MAIL_RESTORE_SUBJECT = {
    [0] = "Restored items",
    [1] = "복구된 아이템",
    [2] = "Objets restaurés",
    [3] = "Wiederhergestellte Gegenstände",
    [4] = "恢复的物品",
    [5] = "恢復的物品",
    [6] = "Objetos restaurados",
    [7] = "Objetos restaurados",
    [8] = "Восстановленные предметы",
}

L.MAIL_RESTORE_BODY = {
    [0] = "Hello %s,\n \n these items from your Carbon Copy have been restored by a Game Master.\n \n- Sincerely,\n %s",
    [1] = "%s 님, 안녕하세요.\n \n Carbon Copy로 받은 아이템을 게임 마스터가 복구해 드렸습니다.\n \n- 감사합니다.\n %s",
    [2] = "Bonjour %s,\n \n ces objets de votre Carbon Copy ont été restaurés par un maître de jeu.\n \n- Cordialement,\n %s",
    [3] = "Hallo %s,\n \n diese Gegenstände aus deiner Carbon Copy wurden von einem Spielleiter wiederhergestellt.\n \n- Mit freundlichen Grüßen,\n %s",
    [4] = "%s 你好，\n \n 你的 Carbon Copy 物品已由游戏管理员恢复。\n \n- 此致，\n %s",
    [5] = "%s 你好，\n \n 你的 Carbon Copy 物品已由遊戲管理員恢復。\n \n- 敬上，\n %s",
    [6] = "Hola %s,\n \n un Maestro de Juego ha restaurado estos objetos de tu Carbon Copy.\n \n- Atentamente,\n %s",
    [7] = "Hola %s,\n \n un Maestro de Juego ha restaurado estos objetos de tu Carbon Copy.\n \n- Atentamente,\n %s",
    [8] = "Здравствуйте, %s!\n \n Гейм-мастер восстановил эти предметы из вашей копии Carbon Copy.\n \n- С уважением,\n %s",
}

-- ---------------------------------------------------------------------------
-- Tickets (GM / console)
-- ---------------------------------------------------------------------------
-- Who ran a ticket command. %s = GM name
L.ACTOR_GM = {
    [0] = "GM %s",
    [1] = "GM %s",
    [2] = "MJ %s",
    [3] = "GM %s",
    [4] = "GM %s",
    [5] = "GM %s",
    [6] = "MJ %s",
    [7] = "MJ %s",
    [8] = "ГМ %s",
}
L.ACTOR_CONSOLE = "The console"

-- %s = command, %s = amount given
L.TICKETS_BAD_AMOUNT = {
    [0] = "Too large or negative amount chosen for %s: %s. Max allowed is +1000.",
    [1] = "%s에 너무 크거나 음수인 값을 입력했습니다: %s. 최대 +1000까지 가능합니다.",
    [2] = "Montant trop élevé ou négatif pour %s : %s. Le maximum autorisé est +1000.",
    [3] = "Zu großer oder negativer Betrag für %s: %s. Maximal erlaubt ist +1000.",
    [4] = "%s 的数量过大或为负数：%s。最大允许 +1000。",
    [5] = "%s 的數量過大或為負數：%s。最大允許 +1000。",
    [6] = "Cantidad demasiado alta o negativa para %s: %s. El máximo permitido es +1000.",
    [7] = "Cantidad demasiado alta o negativa para %s: %s. El máximo permitido es +1000.",
    [8] = "Слишком большое или отрицательное значение для %s: %s. Максимум +1000.",
}

L.TICKETS_PLAYER_NOT_FOUND = {
    [0] = "Player name not found.",
    [1] = "플레이어 이름을 찾을 수 없습니다.",
    [2] = "Nom de joueur introuvable.",
    [3] = "Spielername nicht gefunden.",
    [4] = "未找到该玩家名字。",
    [5] = "找不到該玩家名字。",
    [6] = "Nombre de jugador no encontrado.",
    [7] = "Nombre de jugador no encontrado.",
    [8] = "Имя игрока не найдено.",
}

L.TICKETS_ACCOUNT_NOT_FOUND = {
    [0] = "Account name not found.",
    [1] = "계정 이름을 찾을 수 없습니다.",
    [2] = "Nom de compte introuvable.",
    [3] = "Accountname nicht gefunden.",
    [4] = "未找到该账号名。",
    [5] = "找不到該帳號名稱。",
    [6] = "Nombre de cuenta no encontrado.",
    [7] = "Nombre de cuenta no encontrado.",
    [8] = "Имя учётной записи не найдено.",
}

L.TICKETS_CHAR_NOT_FOUND = {
    [0] = "Character name not found. Check spelling.",
    [1] = "캐릭터 이름을 찾을 수 없습니다. 철자를 확인하세요.",
    [2] = "Nom de personnage introuvable. Vérifiez l'orthographe.",
    [3] = "Charaktername nicht gefunden. Prüfe die Schreibweise.",
    [4] = "未找到该角色名字，请检查拼写。",
    [5] = "找不到該角色名字，請檢查拼字。",
    [6] = "Nombre de personaje no encontrado. Revisa la ortografía.",
    [7] = "Nombre de personaje no encontrado. Revisa la ortografía.",
    [8] = "Имя персонажа не найдено. Проверьте написание.",
}

-- %s = amount given, %d = current tickets
L.TICKETS_TOTAL_TOO_LARGE = {
    [0] = "Too large total amount of tickets: %s. Max allowed total is +1000. Current value: %d",
    [1] = "티켓 총량이 너무 많습니다: %s. 최대 총량은 +1000입니다. 현재 값: %d",
    [2] = "Nombre total de tickets trop élevé : %s. Le total maximum est +1000. Valeur actuelle : %d",
    [3] = "Zu hohe Gesamtzahl an Tickets: %s. Maximal erlaubt sind +1000. Aktueller Wert: %d",
    [4] = "票券总数过多：%s。最多允许 +1000。当前值：%d",
    [5] = "票券總數過多：%s。最多允許 +1000。目前值：%d",
    [6] = "Cantidad total de tickets demasiado alta: %s. El total máximo es +1000. Valor actual: %d",
    [7] = "Cantidad total de tickets demasiado alta: %s. El total máximo es +1000. Valor actual: %d",
    [8] = "Слишком много жетонов в сумме: %s. Максимум +1000. Текущее значение: %d",
}

-- %s = amount given, %d = current tickets
L.TICKETS_NOT_ENOUGH_TO_REMOVE = {
    [0] = "The account does not have enough tickets to remove %s. Current value: %d",
    [1] = "계정의 티켓이 부족하여 %s개를 제거할 수 없습니다. 현재 값: %d",
    [2] = "Le compte n'a pas assez de tickets pour en retirer %s. Valeur actuelle : %d",
    [3] = "Der Account hat nicht genug Tickets, um %s zu entfernen. Aktueller Wert: %d",
    [4] = "该账号票券不足，无法移除 %s 张。当前值：%d",
    [5] = "該帳號票券不足，無法移除 %s 張。目前值：%d",
    [6] = "La cuenta no tiene suficientes tickets para quitar %s. Valor actual: %d",
    [7] = "La cuenta no tiene suficientes tickets para quitar %s. Valor actual: %d",
    [8] = "На учётной записи недостаточно жетонов, чтобы снять %s. Текущее значение: %d",
}

-- %s = who (ACTOR_GM / ACTOR_CONSOLE), %s = command, %s = amount, %d = account id, %s = character name
L.TICKETS_ADDED = {
    [0] = "%s has successfully used %s, adding %s tickets to the account %d which belongs to player %s.",
    [1] = "%s 님이 %s 명령으로 티켓 %s개를 계정 %d(플레이어 %s)에 추가했습니다.",
    [2] = "%s a utilisé %s avec succès : %s tickets ajoutés au compte %d du joueur %s.",
    [3] = "%s hat %s erfolgreich verwendet und %s Tickets zum Account %d von Spieler %s hinzugefügt.",
    [4] = "%s 已成功使用 %s，添加了 %s 张票券到账号 %d（玩家 %s）。",
    [5] = "%s 已成功使用 %s，新增了 %s 張票券到帳號 %d（玩家 %s）。",
    [6] = "%s ha usado %s con éxito, añadiendo %s tickets a la cuenta %d del jugador %s.",
    [7] = "%s ha usado %s con éxito, agregando %s tickets a la cuenta %d del jugador %s.",
    [8] = "%s успешно использовал %s: добавлено жетонов: %s на учётную запись %d игрока %s.",
}

-- same values as TICKETS_ADDED
L.TICKETS_REMOVED = {
    [0] = "%s has successfully used %s, removing %s tickets from the account %d which belongs to player %s.",
    [1] = "%s 님이 %s 명령으로 티켓 %s개를 계정 %d(플레이어 %s)에서 제거했습니다.",
    [2] = "%s a utilisé %s avec succès : %s tickets retirés du compte %d du joueur %s.",
    [3] = "%s hat %s erfolgreich verwendet und %s Tickets vom Account %d von Spieler %s entfernt.",
    [4] = "%s 已成功使用 %s，移除了 %s 张票券，账号 %d（玩家 %s）。",
    [5] = "%s 已成功使用 %s，移除了 %s 張票券，帳號 %d（玩家 %s）。",
    [6] = "%s ha usado %s con éxito, quitando %s tickets de la cuenta %d del jugador %s.",
    [7] = "%s ha usado %s con éxito, quitando %s tickets de la cuenta %d del jugador %s.",
    [8] = "%s успешно использовал %s: снято жетонов: %s с учётной записи %d игрока %s.",
}

-- %s = character name, %d = account id, %d = tickets
L.TICKETS_LOOKUP_RESULT = {
    [0] = "CarbonCopy tickets for %s (account %d): %d",
    [1] = "%s의 CarbonCopy 티켓 (계정 %d): %d",
    [2] = "Tickets CarbonCopy de %s (compte %d) : %d",
    [3] = "CarbonCopy-Tickets von %s (Account %d): %d",
    [4] = "%s 的 CarbonCopy 票券（账号 %d）：%d",
    [5] = "%s 的 CarbonCopy 票券（帳號 %d）：%d",
    [6] = "Tickets de CarbonCopy de %s (cuenta %d): %d",
    [7] = "Tickets de CarbonCopy de %s (cuenta %d): %d",
    [8] = "Жетоны CarbonCopy персонажа %s (учётная запись %d): %d",
}

-- ---------------------------------------------------------------------------
-- .carboncopy restore (GM / console)
-- ---------------------------------------------------------------------------
L.RESTORE_LOG_DISABLED = {
    [0] = "The mailed-items log is disabled (Config.enableMailItemLog = false).",
    [1] = "우편 아이템 기록이 비활성화되어 있습니다 (Config.enableMailItemLog = false).",
    [2] = "Le journal des objets envoyés est désactivé (Config.enableMailItemLog = false).",
    [3] = "Das Protokoll der verschickten Gegenstände ist deaktiviert (Config.enableMailItemLog = false).",
    [4] = "邮寄物品记录已禁用（Config.enableMailItemLog = false）。",
    [5] = "郵寄物品紀錄已停用（Config.enableMailItemLog = false）。",
    [6] = "El registro de objetos enviados está desactivado (Config.enableMailItemLog = false).",
    [7] = "El registro de objetos enviados está desactivado (Config.enableMailItemLog = false).",
    [8] = "Журнал отправленных предметов отключён (Config.enableMailItemLog = false).",
}

-- %s = character name
L.RESTORE_CHAR_NOT_FOUND = {
    [0] = "Character %s not found.",
    [1] = "캐릭터 %s을(를) 찾을 수 없습니다.",
    [2] = "Personnage %s introuvable.",
    [3] = "Charakter %s nicht gefunden.",
    [4] = "未找到角色 %s。",
    [5] = "找不到角色 %s。",
    [6] = "Personaje %s no encontrado.",
    [7] = "Personaje %s no encontrado.",
    [8] = "Персонаж %s не найден.",
}

-- %s = character name
L.RESTORE_BUSY = {
    [0] = "A restore for %s is still finishing. Try again in a few seconds.",
    [1] = "%s의 복구가 아직 진행 중입니다. 몇 초 후에 다시 시도하세요.",
    [2] = "Une restauration pour %s est encore en cours. Réessayez dans quelques secondes.",
    [3] = "Eine Wiederherstellung für %s läuft noch. Versuche es in ein paar Sekunden erneut.",
    [4] = "%s 的恢复仍在进行中，请几秒后再试。",
    [5] = "%s 的恢復仍在進行中，請幾秒後再試。",
    [6] = "Todavía se está terminando una restauración para %s. Inténtalo en unos segundos.",
    [7] = "Todavía se está terminando una restauración para %s. Inténtalo en unos segundos.",
    [8] = "Восстановление для %s ещё выполняется. Попробуйте через несколько секунд.",
}

-- %s = character name
L.RESTORE_ONLINE = {
    [0] = "%s is online. Items can only be restored while the character is logged out (enchants and gems are written to the database). Add 'kick' to kick and restore.",
    [1] = "%s 캐릭터가 접속 중입니다. 아이템은 캐릭터가 접속 종료 상태일 때만 복구할 수 있습니다 (마법부여와 보석은 데이터베이스에 기록됨). 추방 후 복구하려면 'kick'을 추가하세요.",
    [2] = "%s est en ligne. Les objets ne peuvent être restaurés que personnage déconnecté (enchantements et gemmes sont écrits en base de données). Ajoutez 'kick' pour l'expulser et restaurer.",
    [3] = "%s ist online. Gegenstände können nur wiederhergestellt werden, wenn der Charakter ausgeloggt ist (Verzauberungen und Edelsteine werden in die Datenbank geschrieben). Füge 'kick' hinzu, um ihn zu kicken und wiederherzustellen.",
    [4] = "%s 在线。只有角色离线时才能恢复物品（附魔和宝石写入数据库）。添加 'kick' 可踢下线并恢复。",
    [5] = "%s 在線。只有角色離線時才能恢復物品（附魔和寶石寫入資料庫）。加上 'kick' 可踢下線並恢復。",
    [6] = "%s está conectado. Los objetos solo se pueden restaurar con el personaje desconectado (encantamientos y gemas se escriben en la base de datos). Añade 'kick' para expulsarlo y restaurar.",
    [7] = "%s está conectado. Los objetos solo se pueden restaurar con el personaje desconectado (encantamientos y gemas se escriben en la base de datos). Agrega 'kick' para expulsarlo y restaurar.",
    [8] = "%s в игре. Предметы можно восстановить только когда персонаж вне игры (зачарования и самоцветы записываются в базу данных). Добавьте 'kick', чтобы отключить персонажа и восстановить.",
}

-- %s = character name
L.RESTORE_KICKING = {
    [0] = "Kicking %s. The restore runs once the character is saved and offline.",
    [1] = "%s 캐릭터를 추방합니다. 캐릭터가 저장되고 접속 종료되면 복구가 진행됩니다.",
    [2] = "Expulsion de %s. La restauration démarrera une fois le personnage sauvegardé et déconnecté.",
    [3] = "%s wird gekickt. Die Wiederherstellung startet, sobald der Charakter gespeichert und offline ist.",
    [4] = "正在将 %s 踢下线。角色保存并离线后将开始恢复。",
    [5] = "正在將 %s 踢下線。角色儲存並離線後將開始恢復。",
    [6] = "Expulsando a %s. La restauración se hará cuando el personaje esté guardado y desconectado.",
    [7] = "Expulsando a %s. La restauración se hará cuando el personaje esté guardado y desconectado.",
    [8] = "Отключаем %s. Восстановление начнётся, когда персонаж будет сохранён и выйдет из игры.",
}

-- %s = character name
L.RESTORE_NOT_OFFLINE = {
    [0] = "CarbonCopy restore: %s did not go offline in time. Nothing was restored.",
    [1] = "CarbonCopy 복구: %s 캐릭터가 제시간에 접속 종료되지 않았습니다. 아무것도 복구되지 않았습니다.",
    [2] = "Restauration CarbonCopy : %s ne s'est pas déconnecté à temps. Rien n'a été restauré.",
    [3] = "CarbonCopy-Wiederherstellung: %s ist nicht rechtzeitig offline gegangen. Nichts wurde wiederhergestellt.",
    [4] = "CarbonCopy 恢复：%s 未能及时离线，未恢复任何物品。",
    [5] = "CarbonCopy 恢復：%s 未能及時離線，未恢復任何物品。",
    [6] = "Restauración CarbonCopy: %s no se desconectó a tiempo. No se restauró nada.",
    [7] = "Restauración CarbonCopy: %s no se desconectó a tiempo. No se restauró nada.",
    [8] = "Восстановление CarbonCopy: %s не вышел из игры вовремя. Ничего не восстановлено.",
}

-- %s = character name
L.RESTORE_NO_ITEMS = {
    [0] = "No logged CarbonCopy mail items for %s.",
    [1] = "%s의 CarbonCopy 우편 아이템 기록이 없습니다.",
    [2] = "Aucun objet CarbonCopy envoyé enregistré pour %s.",
    [3] = "Keine protokollierten CarbonCopy-Postgegenstände für %s.",
    [4] = "没有 %s 的 CarbonCopy 邮寄物品记录。",
    [5] = "沒有 %s 的 CarbonCopy 郵寄物品紀錄。",
    [6] = "No hay objetos de CarbonCopy enviados registrados para %s.",
    [7] = "No hay objetos de CarbonCopy enviados registrados para %s.",
    [8] = "Нет записей об отправленных предметах CarbonCopy для %s.",
}

-- %s = character name, %d = copy id
L.RESTORE_NO_ITEMS_COPY = {
    [0] = "No logged CarbonCopy mail items for %s (copy %d).",
    [1] = "%s의 CarbonCopy 우편 아이템 기록이 없습니다 (복사 %d).",
    [2] = "Aucun objet CarbonCopy envoyé enregistré pour %s (copie %d).",
    [3] = "Keine protokollierten CarbonCopy-Postgegenstände für %s (Kopie %d).",
    [4] = "没有 %s 的 CarbonCopy 邮寄物品记录（复制 %d）。",
    [5] = "沒有 %s 的 CarbonCopy 郵寄物品紀錄（複製 %d）。",
    [6] = "No hay objetos de CarbonCopy enviados registrados para %s (copia %d).",
    [7] = "No hay objetos de CarbonCopy enviados registrados para %s (copia %d).",
    [8] = "Нет записей об отправленных предметах CarbonCopy для %s (копия %d).",
}

-- %s = character name, %d = guid
L.RESTORE_LIST_HEADER = {
    [0] = "===== CarbonCopy mailed items for %s (guid %d) =====",
    [1] = "===== %s의 CarbonCopy 우편 아이템 (guid %d) =====",
    [2] = "===== Objets CarbonCopy envoyés à %s (guid %d) =====",
    [3] = "===== CarbonCopy-Postgegenstände für %s (GUID %d) =====",
    [4] = "===== %s 的 CarbonCopy 邮寄物品（guid %d）=====",
    [5] = "===== %s 的 CarbonCopy 郵寄物品（guid %d）=====",
    [6] = "===== Objetos de CarbonCopy enviados a %s (guid %d) =====",
    [7] = "===== Objetos de CarbonCopy enviados a %s (guid %d) =====",
    [8] = "===== Предметы CarbonCopy, отправленные %s (guid %d) =====",
}

-- %s = character name
L.RESTORE_LIST_ONLINE = {
    [0] = "%s is online: locations are as of the last save.",
    [1] = "%s 캐릭터가 접속 중입니다: 위치는 마지막 저장 시점 기준입니다.",
    [2] = "%s est en ligne : les emplacements correspondent à la dernière sauvegarde.",
    [3] = "%s ist online: Die Orte entsprechen dem letzten Speicherstand.",
    [4] = "%s 在线：位置为上次保存时的状态。",
    [5] = "%s 在線：位置為上次儲存時的狀態。",
    [6] = "%s está conectado: las ubicaciones son las del último guardado.",
    [7] = "%s está conectado: las ubicaciones son las del último guardado.",
    [8] = "%s в игре: местоположения указаны на момент последнего сохранения.",
}

-- %d = log id, %d = copy id, %s = kind (copy/restore), %s = date, %s = item, %s = location
L.RESTORE_LIST_ROW = {
    [0] = "#%d copy %d %s %s: %s - %s",
    [1] = "#%d 복사 %d %s %s: %s - %s",
    [2] = "#%d copie %d %s %s : %s - %s",
    [3] = "#%d Kopie %d %s %s: %s - %s",
    [4] = "#%d 复制 %d %s %s：%s - %s",
    [5] = "#%d 複製 %d %s %s：%s - %s",
    [6] = "#%d copia %d %s %s: %s - %s",
    [7] = "#%d copia %d %s %s: %s - %s",
    [8] = "#%d копия %d %s %s: %s - %s",
}

-- prefix for a missing item's location, %s = location
L.RESTORE_MISSING = {
    [0] = "MISSING, %s",
    [1] = "없음, %s",
    [2] = "MANQUANT, %s",
    [3] = "FEHLT, %s",
    [4] = "缺失，%s",
    [5] = "缺失，%s",
    [6] = "FALTA, %s",
    [7] = "FALTA, %s",
    [8] = "ОТСУТСТВУЕТ, %s",
}

-- %d = items, %d = missing, %s = character name
L.RESTORE_LIST_FOOTER = {
    [0] = "%d item(s), %d missing. Use: .carboncopy restore %s missing|all [copyId] [kick]",
    [1] = "아이템 %d개, 없음 %d개. 사용법: .carboncopy restore %s missing|all [copyId] [kick]",
    [2] = "%d objet(s), %d manquant(s). Utilisation : .carboncopy restore %s missing|all [copyId] [kick]",
    [3] = "%d Gegenstand/Gegenstände, %d fehlen. Verwendung: .carboncopy restore %s missing|all [copyId] [kick]",
    [4] = "共 %d 件物品，缺失 %d 件。用法：.carboncopy restore %s missing|all [copyId] [kick]",
    [5] = "共 %d 件物品，缺失 %d 件。用法：.carboncopy restore %s missing|all [copyId] [kick]",
    [6] = "%d objeto(s), %d faltan. Uso: .carboncopy restore %s missing|all [copyId] [kick]",
    [7] = "%d objeto(s), %d faltan. Uso: .carboncopy restore %s missing|all [copyId] [kick]",
    [8] = "Предметов: %d, отсутствует: %d. Использование: .carboncopy restore %s missing|all [copyId] [kick]",
}

-- %d = count
L.RESTORE_SKIPPED_UNKNOWN = {
    [0] = "%d item(s) skipped: their entry no longer exists in item_template.",
    [1] = "아이템 %d개를 건너뛰었습니다: item_template에 더 이상 존재하지 않습니다.",
    [2] = "%d objet(s) ignoré(s) : leur entrée n'existe plus dans item_template.",
    [3] = "%d Gegenstand/Gegenstände übersprungen: Der Eintrag existiert nicht mehr in item_template.",
    [4] = "已跳过 %d 件物品：item_template 中已不存在该条目。",
    [5] = "已略過 %d 件物品：item_template 中已不存在該條目。",
    [6] = "%d objeto(s) omitido(s): su entrada ya no existe en item_template.",
    [7] = "%d objeto(s) omitido(s): su entrada ya no existe en item_template.",
    [8] = "Пропущено предметов: %d — их записи больше нет в item_template.",
}

-- %s = character name, %s = mode
L.RESTORE_NOTHING = {
    [0] = "Nothing to restore for %s (%s).",
    [1] = "%s에게 복구할 것이 없습니다 (%s).",
    [2] = "Rien à restaurer pour %s (%s).",
    [3] = "Nichts wiederherzustellen für %s (%s).",
    [4] = "%s 没有需要恢复的物品（%s）。",
    [5] = "%s 沒有需要恢復的物品（%s）。",
    [6] = "Nada que restaurar para %s (%s).",
    [7] = "Nada que restaurar para %s (%s).",
    [8] = "Нечего восстанавливать для %s (%s).",
}

L.RESTORE_NONE_MAILED = {
    [0] = "No items were mailed.",
    [1] = "우편으로 보낸 아이템이 없습니다.",
    [2] = "Aucun objet n'a été envoyé.",
    [3] = "Es wurden keine Gegenstände verschickt.",
    [4] = "没有邮寄任何物品。",
    [5] = "沒有郵寄任何物品。",
    [6] = "No se envió ningún objeto.",
    [7] = "No se envió ningún objeto.",
    [8] = "Предметы не были отправлены.",
}

-- %d = count, %s = character name, %s = mode, %s = character name
L.RESTORE_MAILING = {
    [0] = "Mailing %d item(s) to %s (%s). Enchants are applied in a few seconds, %s is locked out until then.",
    [1] = "아이템 %d개를 %s에게 우편으로 보냅니다 (%s). 몇 초 후 마법부여가 적용되며, 그때까지 %s은(는) 접속할 수 없습니다.",
    [2] = "Envoi de %d objet(s) à %s (%s). Les enchantements seront appliqués dans quelques secondes ; %s est bloqué d'ici là.",
    [3] = "Verschicke %d Gegenstand/Gegenstände an %s (%s). Verzauberungen werden in ein paar Sekunden angewendet, bis dahin ist %s gesperrt.",
    [4] = "正在邮寄 %d 件物品给 %s（%s）。附魔将在几秒后应用，在此之前 %s 无法登录。",
    [5] = "正在郵寄 %d 件物品給 %s（%s）。附魔將在幾秒後套用，在此之前 %s 無法登入。",
    [6] = "Enviando %d objeto(s) a %s (%s). Los encantamientos se aplican en unos segundos; hasta entonces %s está bloqueado.",
    [7] = "Enviando %d objeto(s) a %s (%s). Los encantamientos se aplican en unos segundos; hasta entonces %s está bloqueado.",
    [8] = "Отправка предметов (%d) персонажу %s (%s). Зачарования будут применены через несколько секунд, до тех пор %s заблокирован.",
}

-- %d = count, %s = character name, %s = mode, %s = character name
L.RESTORE_DONE = {
    [0] = "CarbonCopy restore: %d item(s) mailed to %s (%s). %s can log in again.",
    [1] = "CarbonCopy 복구: 아이템 %d개를 %s에게 보냈습니다 (%s). 이제 %s(으)로 다시 접속할 수 있습니다.",
    [2] = "Restauration CarbonCopy : %d objet(s) envoyé(s) à %s (%s). %s peut de nouveau se connecter.",
    [3] = "CarbonCopy-Wiederherstellung: %d Gegenstand/Gegenstände an %s verschickt (%s). %s kann sich wieder einloggen.",
    [4] = "CarbonCopy 恢复：已邮寄 %d 件物品给 %s（%s）。%s 现在可以重新登录。",
    [5] = "CarbonCopy 恢復：已郵寄 %d 件物品給 %s（%s）。%s 現在可以重新登入。",
    [6] = "Restauración CarbonCopy: %d objeto(s) enviado(s) a %s (%s). %s ya puede volver a conectarse.",
    [7] = "Restauración CarbonCopy: %d objeto(s) enviado(s) a %s (%s). %s ya puede volver a conectarse.",
    [8] = "Восстановление CarbonCopy: отправлено предметов: %d персонажу %s (%s). %s снова может войти в игру.",
}

-- Where a mailed item is now (restore list)
L.LOC_EQUIPPED       = { [0] = "equipped",        [1] = "착용 중",        [2] = "équipé",            [3] = "angelegt",          [4] = "已装备",     [5] = "已裝備",     [6] = "equipado",          [7] = "equipado",          [8] = "надето" }
L.LOC_EQUIPPED_BAG   = { [0] = "equipped bag",    [1] = "착용 가방",      [2] = "sac équipé",        [3] = "angelegte Tasche",  [4] = "已装备的背包", [5] = "已裝備的背包", [6] = "bolsa equipada",    [7] = "bolsa equipada",    [8] = "надетая сумка" }
L.LOC_BACKPACK       = { [0] = "backpack",        [1] = "배낭",           [2] = "sac à dos",         [3] = "Rucksack",          [4] = "行囊",       [5] = "行囊",       [6] = "mochila",           [7] = "mochila",           [8] = "рюкзак" }
L.LOC_BAGS           = { [0] = "bags",            [1] = "가방",           [2] = "sacs",              [3] = "Taschen",           [4] = "背包",       [5] = "背包",       [6] = "bolsas",            [7] = "bolsas",            [8] = "сумки" }
L.LOC_BANK           = { [0] = "bank",            [1] = "은행",           [2] = "banque",            [3] = "Bank",              [4] = "银行",       [5] = "銀行",       [6] = "banco",             [7] = "banco",             [8] = "банк" }
L.LOC_BANK_IN_BAG    = { [0] = "bank (in a bag)", [1] = "은행 (가방 안)", [2] = "banque (dans un sac)", [3] = "Bank (in einer Tasche)", [4] = "银行（背包内）", [5] = "銀行（背包內）", [6] = "banco (en una bolsa)", [7] = "banco (en una bolsa)", [8] = "банк (в сумке)" }
L.LOC_BANK_BAG_SLOT  = { [0] = "bank bag slot",   [1] = "은행 가방 칸",   [2] = "emplacement de sac de banque", [3] = "Bankfach für Taschen", [4] = "银行背包栏", [5] = "銀行背包欄", [6] = "hueco de bolsa del banco", [7] = "hueco de bolsa del banco", [8] = "ячейка сумки банка" }
L.LOC_KEYRING        = { [0] = "keyring",         [1] = "열쇠고리",       [2] = "trousseau",         [3] = "Schlüsselbund",     [4] = "钥匙链",     [5] = "鑰匙圈",     [6] = "llavero",           [7] = "llavero",           [8] = "связка ключей" }
L.LOC_INVENTORY      = { [0] = "inventory",       [1] = "소지품",         [2] = "inventaire",        [3] = "Inventar",          [4] = "物品栏",     [5] = "物品欄",     [6] = "inventario",        [7] = "inventario",        [8] = "инвентарь" }
L.LOC_AUCTION        = { [0] = "auction house",   [1] = "경매장",         [2] = "hôtel des ventes",  [3] = "Auktionshaus",      [4] = "拍卖行",     [5] = "拍賣場",     [6] = "casa de subastas",  [7] = "casa de subastas",  [8] = "аукцион" }
L.LOC_GUILD_BANK     = { [0] = "guild bank",      [1] = "길드 은행",      [2] = "banque de guilde",  [3] = "Gildenbank",        [4] = "公会银行",   [5] = "公會銀行",   [6] = "banco de hermandad", [7] = "banco de hermandad", [8] = "банк гильдии" }
L.LOC_MAIL_LOST      = { [0] = "mail was returned to nobody (lost)", [1] = "우편이 받는 사람 없이 반송됨 (분실)", [2] = "courrier renvoyé à personne (perdu)", [3] = "Post an niemanden zurückgeschickt (verloren)", [4] = "邮件被退回给无人（已丢失）", [5] = "郵件被退回給無人（已遺失）", [6] = "correo devuelto a nadie (perdido)", [7] = "correo devuelto a nadie (perdido)", [8] = "письмо возвращено в никуда (утеряно)" }
L.LOC_ORPHANED       = { [0] = "orphaned (not in any container)", [1] = "고아 아이템 (어느 보관함에도 없음)", [2] = "orphelin (dans aucun conteneur)", [3] = "verwaist (in keinem Behälter)", [4] = "孤立（不在任何容器中）", [5] = "孤立（不在任何容器中）", [6] = "huérfano (en ningún contenedor)", [7] = "huérfano (en ningún contenedor)", [8] = "потерян (не в контейнере)" }
L.LOC_GONE           = { [0] = "gone (sold, destroyed or mail deleted)", [1] = "없음 (판매, 파괴 또는 우편 삭제)", [2] = "disparu (vendu, détruit ou courrier supprimé)", [3] = "weg (verkauft, zerstört oder Post gelöscht)", [4] = "已消失（出售、摧毁或邮件被删除）", [5] = "已消失（出售、摧毀或郵件被刪除）", [6] = "desaparecido (vendido, destruido o correo borrado)", [7] = "desaparecido (vendido, destruido o correo borrado)", [8] = "пропал (продан, уничтожен или письмо удалено)" }
-- %s = character name
L.LOC_OTHER_CHAR     = { [0] = "on another character (%s)", [1] = "다른 캐릭터에게 있음 (%s)", [2] = "sur un autre personnage (%s)", [3] = "bei einem anderen Charakter (%s)", [4] = "在其他角色身上（%s）", [5] = "在其他角色身上（%s）", [6] = "en otro personaje (%s)", [7] = "en otro personaje (%s)", [8] = "у другого персонажа (%s)" }
-- %s = character name
L.LOC_MAIL_OTHER     = { [0] = "in mail to %s",   [1] = "%s에게 보낸 우편 안", [2] = "dans un courrier pour %s", [3] = "in Post an %s", [4] = "在寄给 %s 的邮件中", [5] = "在寄給 %s 的郵件中", [6] = "en un correo para %s", [7] = "en un correo para %s", [8] = "в письме для %s" }
-- %d = mail id
L.LOC_MAILBOX        = { [0] = "mailbox (mail %d)", [1] = "우편함 (우편 %d)", [2] = "boîte aux lettres (courrier %d)", [3] = "Briefkasten (Post %d)", [4] = "邮箱（邮件 %d）", [5] = "信箱（郵件 %d）", [6] = "buzón (correo %d)", [7] = "buzón (correo %d)", [8] = "почтовый ящик (письмо %d)" }

-- ---------------------------------------------------------------------------
-- Command syntax, logs viewer and config dump (GM / console).
-- English only; add [1]..[8] entries the same way if you want them translated.
-- ---------------------------------------------------------------------------
L.SYNTAX_COPY             = { [0] = "Syntax: .carboncopy $newCharacterName" }
L.SYNTAX_CONFIG           = { [0] = "Syntax: .carboncopy config" }
L.SYNTAX_TICKETS_LOOKUP   = { [0] = "Syntax: .carboncopy tickets lookup $characterName" }
L.SYNTAX_TICKETS_ADD      = { [0] = "Syntax: .carboncopy tickets add $characterName $amount" }
L.SYNTAX_TICKETS_REMOVE   = { [0] = "Syntax: .carboncopy tickets remove $characterName $amount" }
L.SYNTAX_LOGS             = { [0] = "Syntax: .carboncopy logs [--source name|guid] [--target name|guid] [--day YYYY-MM-DD] [--code N] [--limit N] [--oldest]" }
L.SYNTAX_RESTORE_LIST     = { [0] = "Syntax: .carboncopy restore $characterName                         (list mailed items and where they are now)" }
L.SYNTAX_RESTORE_MISSING  = { [0] = "Syntax: .carboncopy restore $characterName missing [copyId] [kick]  (re-send only items that no longer exist)" }
L.SYNTAX_RESTORE_ALL      = { [0] = "Syntax: .carboncopy restore $characterName all [copyId] [kick]      (re-send every logged item)" }
L.SYNTAX_RESTORE_KICK     = { [0] = "        kick = kick the character if online and restore once it is saved and offline" }
L.SYNTAX_ADDCCTICKETS     = { [0] = "Syntax: .addcctickets $characterName $amount" }
L.SYNTAX_CCACCOUNTTICKETS = { [0] = "Syntax: CCACCOUNTTICKETS $accountName $amount" }
L.CONSOLE_COPY_INGAME     = { [0] = ".carboncopy $newCharacterName can only be run in game, from the character to copy." }

L.CONFIG_HEADER = { [0] = "===== CarbonCopy configuration =====" }
L.CONFIG_FOOTER = { [0] = "===================================" }

L.LOGS_HELP = { [0] = {
    "===== .carboncopy logs flags (all optional) =====",
    "  --source  name|guid   filter by source name or GUID",
    "  --target  name|guid   filter by target name or GUID",
    "  --day     YYYY-MM-DD  entries from this date only",
    "  --code    N           filter by status code:",
    "                          0=free ticket  1=success  2=failed",
    "  --limit   N           max rows 1-100 (default 20)",
    "  --oldest              sort oldest-first (default: newest)",
    "================================================",
} }
L.LOGS_BAD_CODE     = { [0] = "--code must be a non-negative number. Code filter ignored." }
L.LOGS_BAD_LIMIT    = { [0] = "--limit must be 1-100. Using default 20." }
L.LOGS_UNKNOWN_FLAG = { [0] = "Unknown flag: %s. Use 'help' or '--help' for usage." }
L.LOGS_BAD_DAY      = { [0] = "--day must be YYYY-MM-DD. Day filter ignored." }
L.LOGS_TITLE        = { [0] = "========== CarbonCopy Player Logs ==========" }
-- %s = filters, %d = limit, %s = order
L.LOGS_FILTERS      = { [0] = "Filters: %s  |  limit:%d  |  %s" }
L.LOGS_COLUMNS      = { [0] = "  Time (MM-DD HH:MM)  Source (guid) [lv]  ->  Target (guid)  tix:before=>after  Reason" }
L.LOGS_RULE         = { [0] = "--------------------------------------------" }
L.LOGS_NONE         = { [0] = "  (no entries found matching the filters)" }
L.LOGS_END          = { [0] = "============================================" }
-- %d = results, %d = limit, %s = order
L.LOGS_SUMMARY      = { [0] = "%d result(s)  |  limit %d  |  %s" }
L.LOGS_OLDEST_FIRST = { [0] = "oldest first" }
L.LOGS_NEWEST_FIRST = { [0] = "newest first" }

return L
