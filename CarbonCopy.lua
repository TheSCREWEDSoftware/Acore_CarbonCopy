--
-- Created by IntelliJ IDEA.
-- User: Silvia
-- Date: 18/02/2021
-- Time: 23:28
-- To change this template use File | Settings | File Templates.
-- Originally created by Honey for Azerothcore
-- requires ElunaLua module

------------------------------------------------------------------------------------------------
-- ADMIN GUIDE:  -  compile the core with ElunaLua module
--               -  adjust config in Acore_CarbonCopy/CarbonCopy_Config.lua
--               -  adjust texts / translations in Acore_CarbonCopy/CarbonCopy_Locale.lua
--               -  add this script to ../lua_scripts/
--               -  grant account related tickets in the `carboncopy` table
-- PLAYER USAGE: 1) create a new character with same class/race as the one to copy in the same account. Do NOT log it in
--               2) log in with the source character
--               3) .carboncopy newToonsName
------------------------------------------------------------------------------------------------

local CarbonCopyConfig = require("CarbonCopy_Config")
local L = require("CarbonCopy_Locale")

-- All texts live in CarbonCopy_Locale.lua.
-- cc_tl(locale, key, ...) : text for a locale id (falls back to enUS [0]), string.format'ed with the values.
-- cc_t(player, key, ...)  : same, for the player's client locale (player nil = console / log = enUS).
local function cc_tl(locale, key, ...)
    local entry = L[key]
    local text = (type(entry) == "table" and (entry[locale or 0] or entry[0])) or entry or key
    if select('#', ...) > 0 then
        return string.format(text, ...)
    end
    return text
end

local function cc_t(player, key, ...)
    return cc_tl(player and player:GetDbcLocale() or 0, key, ...)
end
local cc_info = cc_t

-- "GM Name" or "The console", for the ticket messages
local function cc_actor(player)
    if player == nil then
        return cc_t(nil, "ACTOR_CONSOLE")
    end
    return cc_t(player, "ACTOR_GM", player:GetName())
end

local Config = CarbonCopyConfig.Config
local cc_maps = CarbonCopyConfig.cc_maps
local ticket_Cost = CarbonCopyConfig.ticket_Cost

-- Settings (see CarbonCopy_Config.lua). Each fallback below is what CarbonCopy did before the option existed,
-- so an older config file without these keys keeps the old behaviour.
local cc_carboncopyTable = Config.carboncopyTableName or "carboncopy"
local cc_playerLogsTable = Config.playerLogsTableName or "carboncopy_player_logs"
local cc_adminLogsTable = Config.adminLogsTableName or "carboncopy_admin_logs"
local cc_mailItemsTable = Config.mailItemsTableName or "carboncopy_mail_items"
local cc_enablePlayerLogs = Config.enablePlayerLogs ~= false
local cc_enableAdminLogs = Config.enableAdminLogs ~= false
local cc_enableMailItemLog = Config.enableMailItemLog ~= false
local cc_mailLogRetentionDays = math.max(0, math.floor(tonumber(Config.mailItemLogRetentionDays) or 0))
local cc_minGMRankForRestore = tonumber(Config.minGMRankForRestore) or tonumber(Config.minGMRankForTickets) or 2

local cc_makeCopySoulbounded = Config.makeCopySoulbounded ~= false
local cc_resetTalentsAfterCopy = Config.resetTalentsAfterCopy == true
local cc_teleportToCapital = Config.teleportToCapital == true
local cc_homebindToCapital = Config.homebindToCapital == true
local cc_allianceRaces = Config.allianceRaces or { 1, 3, 4, 7, 11 }
local cc_hordeRaces = Config.hordeRaces or { 2, 5, 6, 8, 10 }
local cc_capitalPositions = Config.capitalPositions or {
    alliance = { map = 0, zone = 1519, x = -8865.09,   y = 671.793,   z = 97.9034,   o = 2.16098 },  -- Stormwind, Trade District
    horde    = { map = 1, zone = 1637, x = 1633.8,     y = -4440.47,  z = 15.634,    o = 3.08343 },  -- Orgrimmar, Valley of Strength
    neutral  = { map = 0, zone = 33,   x = -14468.104, y = 483.00665, z = 26.776731, o = 0.0 },      -- Booty Bay
}
local CC_CONTINENTS = { 0, 1, 530, 571 }   -- maps a Hearthstone bind point may be on

local cc_mailExpireDays = tonumber(Config.mailExpireDays) or -1
local cc_mailSignature = Config.mailSignature or "the team of ChromieCraft!"
local cc_emptySlotFiller = tonumber(Config.emptySlotFiller) or 38
-- Older configs have Config.mailText (the whole English gear mail text after "Hello Name") instead of mailSignature.
-- When it's there and mailSignature isn't, the copy mails use it as before.
local cc_legacyMailText = (Config.mailSignature == nil) and Config.mailText or nil

local cc_doneMessageDelay = math.max(0, tonumber(Config.doneMessageDelay) or 5)

-- Capital position for a race: alliance / horde list, anything else gets the neutral one.
local function cc_capitalForRace(race)
    for _, r in ipairs(cc_allianceRaces) do
        if r == race then return cc_capitalPositions.alliance end
    end
    for _, r in ipairs(cc_hordeRaces) do
        if r == race then return cc_capitalPositions.horde end
    end
    return cc_capitalPositions.neutral
end

-- SQL for the flags of a copied item, from the original's flags (column or number).
local function cc_copyFlagsSql(sourceFlags)
    if cc_makeCopySoulbounded then
        return '(('..sourceFlags..') | 1)'
    end
    return '('..sourceFlags..')'
end

-- Ban reasons used to lock a character during a copy / restore / revoke. The script only ever lifts bans with these reasons.
local CC_BAN_REASON_COPY = "CarbonCopy"
local CC_BAN_REASON_RESTORE = "CarbonCopy restore"
local CC_BAN_REASON_REVOKE = "CarbonCopy revoke"

-- While a character is locked, check every pollIntervalMs (up to pollMaxAttempts times) whether it is offline and
-- its mail is saved, so the lock only lasts as long as the work really takes.
local CC_POLL_MS = math.max(50, tonumber(Config.pollIntervalMs) or 250)
local CC_POLL_MAX = math.max(1, tonumber(Config.pollMaxAttempts) or 60)

-- "Never expires" = 2038-01-01. Kept below 2^31 so no signed 32-bit time math (core or client) can overflow it.
local CC_MAIL_NEVER_EXPIRES = 2145916800
local cc_unpack = table.unpack or unpack


------------------------------------------
-- NO ADJUSTMENTS REQUIRED BELOW THIS LINE
------------------------------------------

--Globals (see cleanup function for non-arrays)
cc_oldItemGuids = {}
cc_newItemGuids = {}
cc_scriptIsBusy = 0
cc_newCharacterName = nil
cc_copyTicketsBefore = nil
cc_copyTicketsAfter = nil
cc_totemMailGuids = {}      -- every item guid in the shaman totem mail (fillers included), used to find the mail
cc_totemItemGuids = {}      -- only the real totems, used for the mailed-items log
cc_fixItemsAttempts = 0
cc_restoreBusy = {}         -- target guid -> true while a restore for that character is being finalised
cc_copyLocale = 0           -- locale of the copying player, used for the copy mails
cc_copyAccountId = nil      -- account charged for the running copy
cc_copyCharged = 0          -- tickets taken for the running copy (refunded if it fails before anything is mailed)
cc_copyMailed = false       -- true once copy mails went out (no refund after that)
cc_copyStartedAt = nil      -- os.time() the running copy started, for the watchdog

-- If module runs for the first time, create the db specified in Config.dbName and add the "carboncopy" table to it.
CharDBQuery('CREATE DATABASE IF NOT EXISTS `'..Config.customDbName..'`;');
CharDBQuery('CREATE TABLE IF NOT EXISTS `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` ('
    ..'`account_id` INT(11) NOT NULL, '
    ..'`tickets` INT(11) DEFAULT 0, '
    ..'`allow_copy_from_id` INT(11) DEFAULT 0, '
    ..'PRIMARY KEY (`account_id`)'
    ..') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DEFAULT;'
)

if cc_enablePlayerLogs then
    CharDBQuery('CREATE TABLE IF NOT EXISTS `'..Config.customDbName..'`.`'..cc_playerLogsTable..'` ('
        ..'`source_name` VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL, '
        ..'`source_guid` INT(11) NOT NULL, '
        ..'`target_name` VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL, '
        ..'`target_guid` INT(11) DEFAULT NULL, '
        ..'`source_level` TINYINT UNSIGNED DEFAULT NULL, '
        ..'`tickets_before` INT(11) DEFAULT NULL, '
        ..'`tickets_after` INT(11) DEFAULT NULL, '
        ..'`status_code` TINYINT UNSIGNED NOT NULL COMMENT "0=FREE_CONFIG_TICKET,1=SUCCESS,2=FAILED", '
        ..'`reason` VARCHAR(255) DEFAULT NULL, '
        ..'`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, '
        ..'KEY `idx_ccpl_source_guid` (`source_guid`), '
        ..'KEY `idx_ccpl_target_guid` (`target_guid`), '
        ..'KEY `idx_ccpl_status_code` (`status_code`), '
        ..'KEY `idx_ccpl_created_at` (`created_at`)'
        ..') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DEFAULT;'
    )
end

if cc_enableAdminLogs then
    CharDBQuery('CREATE TABLE IF NOT EXISTS `'..Config.customDbName..'`.`'..cc_adminLogsTable..'` ('
        ..'`source_name` VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL, '
        ..'`source_guid` INT(11) DEFAULT NULL, '
        ..'`target_name` VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL, '
        ..'`target_guid` INT(11) DEFAULT NULL, '
        ..'`target_level` TINYINT UNSIGNED DEFAULT NULL, '
        ..'`action_code` TINYINT UNSIGNED NOT NULL COMMENT "3=GM_ADD,4=GM_REMOVE,5=GM_LOOKUP,6=GM_RESTORE,7=GM_REVOKE,8=GM_CLEANUP", '
        ..'`tickets_before` INT(11) DEFAULT NULL, '
        ..'`tickets_after` INT(11) DEFAULT NULL, '
        ..'`status_code` TINYINT UNSIGNED NOT NULL COMMENT "1=SUCCESS,2=FAILED", '
        ..'`reason` VARCHAR(255) DEFAULT NULL, '
        ..'`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, '
        ..'KEY `idx_ccal_source_guid` (`source_guid`), '
        ..'KEY `idx_ccal_target_guid` (`target_guid`), '
        ..'KEY `idx_ccal_action_code` (`action_code`), '
        ..'KEY `idx_ccal_status_code` (`status_code`), '
        ..'KEY `idx_ccal_created_at` (`created_at`)'
        ..') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DEFAULT;'
    )
end

local CC_STATUS_FREE_CONFIG_TICKET = 0
local CC_STATUS_SUCCESS = 1
local CC_STATUS_FAILED = 2
local CC_ACTION_GM_ADD = 3
local CC_ACTION_GM_REMOVE = 4
local CC_ACTION_GM_LOOKUP = 5
local CC_ACTION_GM_RESTORE = 6
local CC_ACTION_GM_REVOKE = 7
local CC_ACTION_GM_CLEANUP = 8

-- Every item mailed by a copy (or by a restore) with a snapshot of its enchants/gems/suffix, so an admin can re-send it.
-- A row with superseded_by_id set has been replaced by a restored copy and is no longer considered.
if cc_enableMailItemLog then
    CharDBQuery('CREATE TABLE IF NOT EXISTS `'..Config.customDbName..'`.`'..cc_mailItemsTable..'` ('
        ..'`id` INT UNSIGNED NOT NULL AUTO_INCREMENT, '
        ..'`copy_id` INT UNSIGNED NOT NULL, '
        ..'`kind` VARCHAR(8) NOT NULL DEFAULT "copy" COMMENT "copy or restore", '
        ..'`source_guid` INT UNSIGNED DEFAULT NULL, '
        ..'`source_name` VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL, '
        ..'`target_guid` INT UNSIGNED NOT NULL, '
        ..'`target_name` VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL, '
        ..'`item_entry` INT UNSIGNED NOT NULL, '
        ..'`source_item_guid` INT UNSIGNED DEFAULT NULL COMMENT "item on the source character it was copied from", '
        ..'`item_guid` INT UNSIGNED NOT NULL COMMENT "the mailed item", '
        ..'`mail_id` INT UNSIGNED DEFAULT NULL, '
        ..'`creator_guid` INT UNSIGNED NOT NULL DEFAULT 0, '
        ..'`duration` INT NOT NULL DEFAULT 0, '
        ..'`charges` VARCHAR(255) NOT NULL DEFAULT "", '
        ..'`flags` INT UNSIGNED NOT NULL DEFAULT 0, '
        ..'`enchantments` TEXT NOT NULL, '
        ..'`random_property_id` SMALLINT NOT NULL DEFAULT 0, '
        ..'`restored_from_id` INT UNSIGNED DEFAULT NULL, '
        ..'`superseded_by_id` INT UNSIGNED DEFAULT NULL, '
        ..'`restored_by` VARCHAR(32) DEFAULT NULL, '
        ..'`revoked_at` TIMESTAMP NULL DEFAULT NULL, '
        ..'`revoked_by` VARCHAR(32) DEFAULT NULL, '
        ..'`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, '
        ..'PRIMARY KEY (`id`), '
        ..'KEY `idx_ccmi_target_guid` (`target_guid`), '
        ..'KEY `idx_ccmi_item_guid` (`item_guid`), '
        ..'KEY `idx_ccmi_copy_id` (`copy_id`)'
        ..') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci ROW_FORMAT=DEFAULT;'
    )
    -- tables created before .carboncopy revoke existed: add its columns
    for _, column in ipairs({ { "revoked_at", "TIMESTAMP NULL DEFAULT NULL" }, { "revoked_by", "VARCHAR(32) DEFAULT NULL" } }) do
        if CharDBQuery("SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = '"..Config.customDbName.."' AND TABLE_NAME = '"
            ..cc_mailItemsTable.."' AND COLUMN_NAME = '"..column[1].."' LIMIT 1;") == nil then
            CharDBQuery('ALTER TABLE `'..Config.customDbName..'`.`'..cc_mailItemsTable..'` ADD COLUMN `'..column[1]..'` '..column[2]..';')
        end
    end
end

local function cc_sqlQuote(value)
    if value == nil then
        return "NULL"
    end

    local escaped = tostring(value):gsub("\\", "\\\\"):gsub("'", "''")
    return "'"..escaped.."'"
end

local function cc_sqlNumber(value)
    if value == nil then
        return "NULL"
    end
    return tostring(value)
end

local function cc_logPlayer(sourceName, sourceGuid, targetName, targetGuid, sourceLevel, ticketsBefore, ticketsAfter, statusCode, reason)
    if not cc_enablePlayerLogs then
        return
    end

    CharDBQuery('INSERT INTO `'..Config.customDbName..'`.`'..cc_playerLogsTable..'` ('
        ..'`source_name`, `source_guid`, `target_name`, `target_guid`, `source_level`, '
        ..'`tickets_before`, `tickets_after`, `status_code`, `reason`'
        ..') VALUES ('
        ..cc_sqlQuote(sourceName)..', '
        ..cc_sqlNumber(sourceGuid)..', '
        ..cc_sqlQuote(targetName)..', '
        ..cc_sqlNumber(targetGuid)..', '
        ..cc_sqlNumber(sourceLevel)..', '
        ..cc_sqlNumber(ticketsBefore)..', '
        ..cc_sqlNumber(ticketsAfter)..', '
        ..cc_sqlNumber(statusCode)..', '
        ..cc_sqlQuote(reason)
        ..');'
    )
end

local function cc_logAdmin(sourceName, sourceGuid, targetName, targetGuid, targetLevel, actionCode, ticketsBefore, ticketsAfter, statusCode, reason)
    if not cc_enableAdminLogs then
        return
    end

    CharDBQuery('INSERT INTO `'..Config.customDbName..'`.`'..cc_adminLogsTable..'` ('
        ..'`source_name`, `source_guid`, `target_name`, `target_guid`, `target_level`, '
        ..'`action_code`, `tickets_before`, `tickets_after`, `status_code`, `reason`'
        ..') VALUES ('
        ..cc_sqlQuote(sourceName)..', '
        ..cc_sqlNumber(sourceGuid)..', '
        ..cc_sqlQuote(targetName)..', '
        ..cc_sqlNumber(targetGuid)..', '
        ..cc_sqlNumber(targetLevel)..', '
        ..cc_sqlNumber(actionCode)..', '
        ..cc_sqlNumber(ticketsBefore)..', '
        ..cc_sqlNumber(ticketsAfter)..', '
        ..cc_sqlNumber(statusCode)..', '
        ..cc_sqlQuote(reason)
        ..');'
    )
end

local function cc_sortedKeys(tbl)
    local keys = {}
    for key in pairs(tbl) do
        table.insert(keys, key)
    end

    table.sort(keys, function(a, b)
        local typeA = type(a)
        local typeB = type(b)
        if typeA == typeB then
            if typeA == "number" then
                return a < b
            end
            return tostring(a) < tostring(b)
        end

        return typeA < typeB
    end)

    return keys
end

local function cc_sendTableDump(chatHandler, title, tbl)
    chatHandler:SendSysMessage(title)
    for _, key in ipairs(cc_sortedKeys(tbl)) do
        chatHandler:SendSysMessage("  ["..tostring(key).."] = "..tostring(tbl[key]))
    end
end

local function cc_formatDisplayValue(value)
    if type(value) ~= "string" then
        return tostring(value)
    end

    local compact = value:gsub("%s+", " ")
    compact = compact:gsub("^%s+", "")
    compact = compact:gsub("%s+$", "")
    return compact
end

local function cc_execConfigCommand(chatHandler)
    chatHandler:SendSysMessage(cc_t(nil, "CONFIG_HEADER"))

    for _, key in ipairs(cc_sortedKeys(Config)) do
        local value = Config[key]
        if type(value) ~= "table" then
            chatHandler:SendSysMessage("  "..tostring(key).." = "..cc_formatDisplayValue(value))
        end
    end

    cc_sendTableDump(chatHandler, "  cc_maps:", cc_maps)
    cc_sendTableDump(chatHandler, "  ticket_Cost:", ticket_Cost)

    chatHandler:SendSysMessage(cc_t(nil, "CONFIG_FOOTER"))
end

-- cc_execLogsCommand: shared handler for ".carboncopy logs" from console or GM.
local function cc_execLogsCommand(chatHandler, commandArray, startIdx)
    -- Help subcommand
    local firstArg = commandArray[startIdx] and string.lower(commandArray[startIdx]) or nil
    if firstArg == "help" or firstArg == "--help" then
        for _, line in ipairs(L.LOGS_HELP[0]) do
            chatHandler:SendSysMessage(line)
        end
        return
    end

    local filterSource  = nil
    local filterTarget  = nil
    local filterDay     = nil
    local filterCode    = nil
    local limitN        = 20
    local orderOldest   = false
    local parseError    = false

    local i = startIdx
    while i <= #commandArray do
        local flag = string.lower(commandArray[i])
        if flag == "--source" then
            i = i + 1
            if commandArray[i] ~= nil then filterSource = commandArray[i] end
        elseif flag == "--target" then
            i = i + 1
            if commandArray[i] ~= nil then filterTarget = commandArray[i] end
        elseif flag == "--day" then
            i = i + 1
            if commandArray[i] ~= nil then filterDay = commandArray[i] end
        elseif flag == "--code" then
            i = i + 1
            if commandArray[i] ~= nil then
                local n = tonumber(commandArray[i])
                if n ~= nil and n >= 0 then
                    filterCode = math.floor(n)
                else
                    chatHandler:SendSysMessage(cc_t(nil, "LOGS_BAD_CODE"))
                end
            end
        elseif flag == "--limit" then
            i = i + 1
            if commandArray[i] ~= nil then
                local n = tonumber(commandArray[i])
                if n ~= nil and n >= 1 and n <= 100 then
                    limitN = math.floor(n)
                else
                    chatHandler:SendSysMessage(cc_t(nil, "LOGS_BAD_LIMIT"))
                end
            end
        elseif flag == "--oldest" then
            orderOldest = true
        else
            chatHandler:SendSysMessage(cc_t(nil, "LOGS_UNKNOWN_FLAG", commandArray[i]))
            parseError = true
            break
        end
        i = i + 1
    end

    if parseError then
        return
    end

    local conditions = {}

    if filterSource ~= nil then
        if tonumber(filterSource) ~= nil then
            table.insert(conditions, '`source_guid` = '..math.floor(tonumber(filterSource)))
        else
            table.insert(conditions, '`source_name` = '..cc_sqlQuote(cc_normalizeCharacterName(filterSource)))
        end
    end

    if filterTarget ~= nil then
        if tonumber(filterTarget) ~= nil then
            table.insert(conditions, '`target_guid` = '..math.floor(tonumber(filterTarget)))
        else
            table.insert(conditions, '`target_name` = '..cc_sqlQuote(cc_normalizeCharacterName(filterTarget)))
        end
    end

    if filterDay ~= nil then
        if filterDay:match("^%d%d%d%d%-%d%d%-%d%d$") then
            table.insert(conditions, 'DATE(`created_at`) = '..cc_sqlQuote(filterDay))
        else
            chatHandler:SendSysMessage(cc_t(nil, "LOGS_BAD_DAY"))
        end
    end

    if filterCode ~= nil then
        table.insert(conditions, '`status_code` = '..filterCode)
    end

    local whereClause = (#conditions > 0) and (" WHERE "..table.concat(conditions, " AND ")) or ""
    local orderDir    = orderOldest and "ASC" or "DESC"

    local sql = 'SELECT `source_name`,`source_guid`,`source_level`,`target_name`,`target_guid`,'
        ..'`tickets_before`,`tickets_after`,`status_code`,`reason`,`created_at`'
        ..' FROM `'..Config.customDbName..'`.`'..cc_playerLogsTable..'`'
        ..whereClause
        ..' ORDER BY `created_at` '..orderDir
        ..' LIMIT '..limitN..';'

    -- Build active-filter summary for header
    local activeFilters = {}
    if filterSource ~= nil then table.insert(activeFilters, "source:"..filterSource) end
    if filterTarget ~= nil then table.insert(activeFilters, "target:"..filterTarget) end
    if filterDay    ~= nil then table.insert(activeFilters, "day:"..filterDay) end
    if filterCode   ~= nil then table.insert(activeFilters, "code:"..filterCode) end
    local filterSummary = (#activeFilters > 0) and table.concat(activeFilters, "  ") or "none"

    -- Header
    chatHandler:SendSysMessage(cc_t(nil, "LOGS_TITLE"))
    chatHandler:SendSysMessage(cc_t(nil, "LOGS_FILTERS", filterSummary, limitN, cc_t(nil, orderOldest and "LOGS_OLDEST_FIRST" or "LOGS_NEWEST_FIRST")))
    chatHandler:SendSysMessage(cc_t(nil, "LOGS_COLUMNS"))
    chatHandler:SendSysMessage(cc_t(nil, "LOGS_RULE"))

    local rows = CharDBQuery(sql)
    if rows == nil then
        chatHandler:SendSysMessage(cc_t(nil, "LOGS_NONE"))
        chatHandler:SendSysMessage(cc_t(nil, "LOGS_END"))
        return
    end

    local count = 0
    repeat
        local sName     = rows:GetString(0)
        local sGuid     = rows:GetUInt32(1)
        local sLevel    = rows:GetUInt8(2)
        local tName     = rows:GetString(3)
        local tGuid     = rows:GetUInt32(4)
        local tickBef   = rows:GetInt32(5)
        local tickAft   = rows:GetInt32(6)
        local reason    = rows:GetString(8)
        local createdAt = rows:GetString(9)

        -- Shorten timestamp to "YYYY-MM-DD HH:MM" from "YYYY-MM-DD HH:MM:SS"
        local timeStr = createdAt:sub(1, 16)

        local srcPart = sName.." (GUID: "..sGuid..") [lv"..sLevel.."]"

        local tgtPart = ""
        if tName ~= nil and tName ~= "" then
            tgtPart = " | "..tName.." (GUID: "..tGuid..")"
        end

        local tickPart
        if tickBef == tickAft then
            tickPart = tostring(tickBef)
        else
            tickPart = tickBef.." => "..tickAft
        end

        local statusCode = rows:GetUInt8(7)
        local reasonPart = reason.." (Code: "..statusCode..")"

        chatHandler:SendSysMessage(timeStr.." | "..srcPart..tgtPart.." | "..tickPart.." | "..reasonPart)
        count = count + 1
    until not rows:NextRow()

    chatHandler:SendSysMessage(cc_t(nil, "LOGS_RULE"))
    chatHandler:SendSysMessage(cc_t(nil, "LOGS_SUMMARY", count, limitN, cc_t(nil, orderOldest and "LOGS_OLDEST_FIRST" or "LOGS_NEWEST_FIRST")))
    chatHandler:SendSysMessage(cc_t(nil, "LOGS_END"))
end

-- Ticket cost to copy a character of this level, or nil if no ticket_Cost bracket covers it.
local function cc_ticketCostForLevel(level)
    if Config.ticketCost == "single" then
        return 1
    end
    local highest = 0
    for bracket in pairs(ticket_Cost) do
        if bracket > highest then
            highest = bracket
        end
    end
    for n = level, highest do
        if ticket_Cost[n] ~= nil then
            return ticket_Cost[n]
        end
    end
    return nil
end

-- Sends the ticket cost per level (only levels that can be copied) and the starter tickets.
local function cc_sendTicketCosts(player, chatHandler)
    chatHandler:SendSysMessage(cc_info(player, "COSTS_HEADER"))
    if Config.ticketCost == "single" then
        chatHandler:SendSysMessage(cc_info(player, "COST_SINGLE"))
    else
        local brackets = {}
        for bracket in pairs(ticket_Cost) do
            table.insert(brackets, bracket)
        end
        table.sort(brackets)
        local from = 1
        for _, to in ipairs(brackets) do
            if from > Config.maxLevel then
                break
            end
            local upTo = math.min(to, Config.maxLevel)
            if from == upTo then
                chatHandler:SendSysMessage(cc_info(player, "COST_LEVEL", from, ticket_Cost[to]))
            else
                chatHandler:SendSysMessage(cc_info(player, "COST_RANGE", from, upTo, ticket_Cost[to]))
            end
            from = to + 1
        end
    end
    chatHandler:SendSysMessage(cc_info(player, "STARTER_TICKETS", Config.freeTickets))
end

------------------------------------------
-- Mail expiry / mailed-items log / restore
------------------------------------------

-- expire_time to put on CarbonCopy mails, or nil to leave the core default (30 days).
local function cc_mailExpireTime()
    if cc_mailExpireDays < 0 then
        return nil
    end
    if cc_mailExpireDays == 0 then
        return CC_MAIL_NEVER_EXPIRES
    end
    return math.min(os.time() + cc_mailExpireDays * 86400, CC_MAIL_NEVER_EXPIRES)
end

-- Pushes the expiry of every mail (to this receiver) that holds one of these items.
local function cc_extendMailForItems(receiverGuid, itemGuids)
    local expire = cc_mailExpireTime()
    if expire == nil or #itemGuids == 0 then
        return
    end
    CharDBQuery('UPDATE `mail` AS m INNER JOIN `mail_items` AS mi ON mi.mail_id = m.id '
        ..'SET m.expire_time = '..expire..' '
        ..'WHERE m.receiver = '..receiverGuid..' AND mi.item_guid IN ('..table.concat(itemGuids, ',')..');')
end

-- Lifts the temporary lock the script put on a character (never touches other bans).
-- The core only checks character_banned.active at login, so this unlocks immediately.
local function cc_liftCarbonCopyBan(characterGuid)
    if characterGuid == nil or characterGuid == 0 then
        return
    end
    CharDBQuery('UPDATE `character_banned` SET `active` = 0 WHERE `guid` = '..characterGuid..' AND `active` = 1 '
        ..'AND `banreason` IN ('..cc_sqlQuote(CC_BAN_REASON_COPY)..', '..cc_sqlQuote(CC_BAN_REASON_RESTORE)..', '..cc_sqlQuote(CC_BAN_REASON_REVOKE)..');')
end

local function cc_itemExists(entry)
    return entry ~= nil and WorldDBQuery('SELECT 1 FROM `item_template` WHERE `entry` = '..entry..' LIMIT 1;') ~= nil
end

-- Mails one of each entry to the receiver, 12 items per mail (GM stationery).
-- Returns the new item guids in the same order as entries (nil where a mail failed).
local function cc_sendItemMails(receiverGuid, subject, body, entries)
    local guids = {}
    local first = 1
    while first <= #entries do
        local last = math.min(first + 11, #entries)
        local args = { subject, body, receiverGuid, 0, 61, 0, 0, 0 }
        for n = first, last do
            table.insert(args, entries[n])
            table.insert(args, 1)
        end
        local result = { pcall(SendMail, cc_unpack(args)) }
        if result[1] then
            for n = first, last do
                guids[n] = result[n - first + 2]
            end
        else
            PrintError("CarbonCopy: SendMail to "..receiverGuid.." failed: "..tostring(result[2]))
        end
        first = last + 1
    end
    return guids
end

-- SendMail commits asynchronously: true once every item is visible in mail_items.
local function cc_mailItemsCommitted(itemGuids)
    if #itemGuids == 0 then
        return true
    end
    local q = CharDBQuery('SELECT `item_guid` FROM `mail_items` WHERE `item_guid` IN ('..table.concat(itemGuids, ',')..');')
    return q ~= nil and q:GetRowCount() >= #itemGuids
end

local function cc_characterNameByGuid(guid)
    if guid == nil then
        return nil
    end
    local q = CharDBQuery('SELECT `name` FROM `characters` WHERE `guid` = '..guid..' LIMIT 1;')
    if q == nil then
        return nil
    end
    return q:GetString(0)
end

-- Item link in game, "Name (entry)" on the console.
local function cc_itemLabel(player, entry)
    if player ~= nil and GetItemLink ~= nil then
        return GetItemLink(entry, player:GetDbcLocale())
    end
    local q = WorldDBQuery('SELECT `name` FROM `item_template` WHERE `entry` = '..entry..' LIMIT 1;')
    if q ~= nil then
        return q:GetString(0).." ("..entry..")"
    end
    return "item "..entry
end

-- Snapshots the mailed item (as it is in item_instance right now) into the mailed-items log.
local function cc_logMailedItem(copyId, kind, sourceGuid, sourceName, targetGuid, targetName, sourceItemGuid, itemGuid, restoredFromId, restoredBy)
    if not cc_enableMailItemLog or itemGuid == nil then
        return
    end
    CharDBQuery('INSERT INTO `'..Config.customDbName..'`.`'..cc_mailItemsTable..'` ('
        ..'`copy_id`, `kind`, `source_guid`, `source_name`, `target_guid`, `target_name`, `item_entry`, `source_item_guid`, '
        ..'`item_guid`, `mail_id`, `creator_guid`, `duration`, `charges`, `flags`, `enchantments`, `random_property_id`, '
        ..'`restored_from_id`, `restored_by`) '
        ..'SELECT '..copyId..', '..cc_sqlQuote(kind)..', '..cc_sqlNumber(sourceGuid)..', '..cc_sqlQuote(sourceName)..', '
        ..targetGuid..', '..cc_sqlQuote(targetName or "?")..', ii.itemEntry, '..cc_sqlNumber(sourceItemGuid)..', '
        ..'ii.guid, (SELECT mi.mail_id FROM `mail_items` AS mi WHERE mi.item_guid = ii.guid LIMIT 1), '
        ..'ii.creatorGuid, ii.duration, COALESCE(ii.charges, SPACE(0)), COALESCE(ii.flags, 0), ii.enchantments, ii.randomPropertyId, '
        ..cc_sqlNumber(restoredFromId)..', '..cc_sqlQuote(restoredBy)..' '
        ..'FROM `item_instance` AS ii WHERE ii.guid = '..itemGuid..';')
end

-- Deletes mailed-items log rows older than `days` days. Returns how many were deleted.
local function cc_cleanupMailLog(days)
    local logTable = '`'..Config.customDbName..'`.`'..cc_mailItemsTable..'`'
    local where = ' WHERE `created_at` < NOW() - INTERVAL '..math.floor(days)..' DAY'
    local q = CharDBQuery('SELECT `id` FROM '..logTable..where..';')
    local count = q ~= nil and q:GetRowCount() or 0
    if count > 0 then
        CharDBQuery('DELETE FROM '..logTable..where..';')
    end
    return count
end

local function cc_nextCopyId()
    local q = CharDBQuery('SELECT MAX(`copy_id`) FROM `'..Config.customDbName..'`.`'..cc_mailItemsTable..'`;')
    if q == nil or q:IsNull(0) then
        return 1
    end
    return q:GetUInt32(0) + 1
end

-- Where a logged item is now. Returns isMissing, location key (CarbonCopy_Locale.lua LOC_*), optional value for it.
-- Anything still owned by the target (bags, bank, keyring, mailbox, auction) or still existing elsewhere
-- (guild bank, another character) is NOT missing; only items that no longer exist (or are lost) are.
local function cc_locateMailedItem(itemGuid, targetGuid)
    local q = CharDBQuery('SELECT `guid`, `bag`, `slot` FROM `character_inventory` WHERE `item` = '..itemGuid..' LIMIT 1;')
    if q ~= nil then
        local owner, bag, slot = q:GetUInt32(0), q:GetUInt32(1), q:GetUInt8(2)
        if owner ~= targetGuid then
            return false, "LOC_OTHER_CHAR", cc_characterNameByGuid(owner) or tostring(owner)
        end
        if bag == 0 then
            if slot < 19 then return false, "LOC_EQUIPPED" end
            if slot < 23 then return false, "LOC_EQUIPPED_BAG" end
            if slot < 39 then return false, "LOC_BACKPACK" end
            if slot < 67 then return false, "LOC_BANK" end
            if slot < 74 then return false, "LOC_BANK_BAG_SLOT" end
            if slot >= 86 and slot < 118 then return false, "LOC_KEYRING" end
            return false, "LOC_INVENTORY"
        end
        local p = CharDBQuery('SELECT `slot` FROM `character_inventory` WHERE `item` = '..bag..' LIMIT 1;')
        if p ~= nil and p:GetUInt8(0) >= 67 and p:GetUInt8(0) < 74 then
            return false, "LOC_BANK_IN_BAG"
        end
        return false, "LOC_BAGS"
    end

    q = CharDBQuery('SELECT `mail_id`, `receiver` FROM `mail_items` WHERE `item_guid` = '..itemGuid..' LIMIT 1;')
    if q ~= nil then
        local mailId, receiver = q:GetUInt32(0), q:GetUInt32(1)
        if receiver == targetGuid then
            return false, "LOC_MAILBOX", mailId
        end
        if receiver == 0 then
            return true, "LOC_MAIL_LOST"
        end
        return false, "LOC_MAIL_OTHER", cc_characterNameByGuid(receiver) or tostring(receiver)
    end

    if CharDBQuery('SELECT 1 FROM `auctionhouse` WHERE `itemguid` = '..itemGuid..' LIMIT 1;') ~= nil then
        return false, "LOC_AUCTION"
    end
    if CharDBQuery('SELECT 1 FROM `guild_bank_item` WHERE `item_guid` = '..itemGuid..' LIMIT 1;') ~= nil then
        return false, "LOC_GUILD_BANK"
    end
    if CharDBQuery('SELECT 1 FROM `item_instance` WHERE `guid` = '..itemGuid..' LIMIT 1;') ~= nil then
        return true, "LOC_ORPHANED"
    end
    return true, "LOC_GONE"
end

-- Tells the admin (in game, in their locale, if still online) and the server log (English) how a delayed restore went.
local function cc_notifyAdmin(adminGuid, key, ...)
    PrintInfo("CarbonCopy: "..cc_tl(0, key, ...))
    if adminGuid ~= nil then
        local admin = GetPlayerByGUID(adminGuid)
        if admin ~= nil then
            admin:SendBroadcastMessage(cc_t(admin, key, ...))
        end
    end
end

-- say(key, ...) sends a locale text: to a ChatHandler (in the player's locale) or, after a delay, via cc_notifyAdmin.
local function cc_chatSay(player, chatHandler)
    return function(key, ...)
        chatHandler:SendSysMessage(cc_t(player, key, ...))
    end
end

local function cc_sendRestoreSyntax(say)
    say("SYNTAX_RESTORE_LIST")
    say("SYNTAX_RESTORE_MISSING")
    say("SYNTAX_RESTORE_ALL")
    say("SYNTAX_RESTORE_KICK")
end

-- Writes enchants/gems/suffix back onto the restored items, keeps the mail, logs the new items, unlocks the character.
-- Runs a few seconds after SendMail so its transaction is committed; retries a few times if not yet.
local function cc_finishRestore(job)
    local newGuids = {}
    for _, pair in ipairs(job.pairs) do
        table.insert(newGuids, pair.newGuid)
    end

    if not cc_mailItemsCommitted(newGuids) and job.attempts < CC_POLL_MAX then
        job.attempts = job.attempts + 1
        CreateLuaEvent(function() cc_finishRestore(job) end, CC_POLL_MS, 1)
        return
    end

    for _, pair in ipairs(job.pairs) do
        local row = pair.row
        CharDBQuery('UPDATE `item_instance` SET `owner_guid` = '..job.targetGuid..', '
            ..'`creatorGuid` = '..row.creatorGuid..', `duration` = '..row.duration..', '
            ..'`charges` = '..cc_sqlQuote(row.charges)..', `flags` = '..cc_copyFlagsSql(row.flags)..', '
            ..'`enchantments` = '..cc_sqlQuote(row.enchantments)..', `randomPropertyId` = '..row.randomPropertyId..' '
            ..'WHERE `guid` = '..pair.newGuid..';')
    end

    cc_extendMailForItems(job.targetGuid, newGuids)

    for _, pair in ipairs(job.pairs) do
      local row = pair.row
      if job.clear then
        -- --clear: everything went fine, drop the restored item's log row and don't log the new copy
        CharDBQuery('DELETE FROM `'..Config.customDbName..'`.`'..cc_mailItemsTable..'` WHERE `id` = '..row.id..';')
      else
        cc_logMailedItem(row.copyId, "restore", row.sourceGuid, row.sourceName, job.targetGuid, job.targetName,
            row.sourceItemGuid, pair.newGuid, row.id, job.adminName)
        local q = CharDBQuery('SELECT `id` FROM `'..Config.customDbName..'`.`'..cc_mailItemsTable..'` '
            ..'WHERE `item_guid` = '..pair.newGuid..' ORDER BY `id` DESC LIMIT 1;')
        if q ~= nil then
            CharDBQuery('UPDATE `'..Config.customDbName..'`.`'..cc_mailItemsTable..'` SET `superseded_by_id` = '..q:GetUInt32(0)
                ..' WHERE `id` = '..row.id..';')
        end
      end
    end

    cc_liftCarbonCopyBan(job.targetGuid)
    cc_restoreBusy[job.targetGuid] = nil
    cc_notifyAdmin(job.adminGuid, job.clear and "RESTORE_DONE_CLEARED" or "RESTORE_DONE", #job.pairs, job.targetName, job.mode, job.targetName)
    cc_logAdmin(job.adminName, job.adminGuid, job.targetName, job.targetGuid, nil, CC_ACTION_GM_RESTORE, nil, nil,
        CC_STATUS_SUCCESS, "Restored "..#job.pairs.." item(s), mode "..job.mode..(job.kicked and ", kicked" or "")..(job.clear and ", log cleared" or ""))
end

-- For restore / revoke: returns true when the caller must stop because the target is online.
-- Without 'kick' it says onlineKey. With 'kick' it locks (which kicks) the character, waits until its logout save is
-- done and calls rerun(notify) - notify(key, ...) reaches the admin later, the ChatHandler is gone by then.
local function cc_requireOffline(targetName, targetGuid, isOnline, kick, kicked, admin, say, banReason, onlineKey, kickingKey, timeoutKey, rerun)
    if not isOnline or kicked then
        return false
    end
    if not kick then
        say(onlineKey, targetName)
        return true
    end
    Ban(1, targetName, 45, banReason, admin.name)
    say(kickingKey, targetName)
    local notify = function(key, ...) cc_notifyAdmin(admin.guid, key, ...) end
    local tries = 0
    local function waitOffline()
        tries = tries + 1
        local o = CharDBQuery('SELECT `online` FROM `characters` WHERE `guid` = '..targetGuid..' LIMIT 1;')
        local offline = GetPlayerByGUID(targetGuid) == nil and (o == nil or o:GetUInt8(0) == 0)
        if offline then
            rerun(notify)
        elseif tries < CC_POLL_MAX then
            CreateLuaEvent(waitOffline, CC_POLL_MS, 1)
        else
            notify(timeoutKey, targetName)
            cc_liftCarbonCopyBan(targetGuid)
        end
    end
    CreateLuaEvent(waitOffline, CC_POLL_MS, 1)
    return true
end

-- .carboncopy restore $name [list|missing|all] [copyId] [--kick] [--clear]   (GM or console)
-- --clear: once the restore went fine, delete the log rows of the restored items instead of logging the new copies.
-- say: function(key, ...) that delivers a locale text (see cc_chatSay / cc_notifyAdmin).
-- admin: { name, guid } of who ran it; kicked: true when re-run after the kick (character already locked).
local function cc_execRestoreCommand(player, say, commandArray, startIdx, admin, kicked)
    admin = admin or { name = player and player:GetName() or "console", guid = player and tonumber(tostring(player:GetGUID())) or nil }

    if not cc_enableMailItemLog then
        say("RESTORE_LOG_DISABLED")
        return
    end
    if commandArray[startIdx] == nil then
        cc_sendRestoreSyntax(say)
        return
    end

    local targetName = cc_normalizeCharacterName(commandArray[startIdx])
    local mode, copyFilter, kick, clear = "list", nil, false, false
    for n = startIdx + 1, startIdx + 4 do
        local token = commandArray[n] and string.lower(commandArray[n])
        if token == nil then
            break
        elseif token == "list" or token == "missing" or token == "all" then
            mode = token
        elseif token == "--kick" then
            kick = true
        elseif token == "--clear" then
            clear = true
        elseif tonumber(token) ~= nil then
            copyFilter = tonumber(token)
        else
            cc_sendRestoreSyntax(say)
            return
        end
    end

    local q = CharDBQuery("SELECT `guid`, `online`, `account` FROM `characters` WHERE `name` = "..cc_sqlQuote(targetName).." LIMIT 1;")
    if q == nil then
        say("RESTORE_CHAR_NOT_FOUND", targetName)
        return
    end
    local targetGuid, targetOnline, targetAccount = q:GetUInt32(0), q:GetUInt8(1), q:GetUInt32(2)
    local isOnline = targetOnline ~= 0 or GetPlayerByGUID(targetGuid) ~= nil

    -- stop here without restoring; unlocks the character if we kicked/locked it
    local function abort(key, ...)
        say(key, ...)
        if kicked then
            cc_liftCarbonCopyBan(targetGuid)
        end
    end

    if mode ~= "list" then
        if cc_restoreBusy[targetGuid] then
            abort("RESTORE_BUSY", targetName)
            return
        end
        if cc_requireOffline(targetName, targetGuid, isOnline, kick, kicked, admin, say, CC_BAN_REASON_RESTORE,
            "RESTORE_ONLINE", "RESTORE_KICKING", "RESTORE_NOT_OFFLINE",
            function(notify) cc_execRestoreCommand(nil, notify, commandArray, startIdx, admin, true) end) then
            return
        end
    end

    local sql = 'SELECT `id`, `copy_id`, `kind`, `item_entry`, `item_guid`, `creator_guid`, `duration`, `charges`, `flags`, '
        ..'`enchantments`, `random_property_id`, `source_guid`, COALESCE(`source_name`, SPACE(0)), `source_item_guid`, '
        ..'DATE_FORMAT(`created_at`, "%Y-%m-%d %H:%i") '
        ..'FROM `'..Config.customDbName..'`.`'..cc_mailItemsTable..'` '
        ..'WHERE `target_guid` = '..targetGuid..' AND `superseded_by_id` IS NULL AND `revoked_at` IS NULL'
    if copyFilter ~= nil then
        sql = sql..' AND `copy_id` = '..copyFilter
    end
    q = CharDBQuery(sql..' ORDER BY `id`;')
    if q == nil then
        if copyFilter ~= nil then
            abort("RESTORE_NO_ITEMS_COPY", targetName, copyFilter)
        else
            abort("RESTORE_NO_ITEMS", targetName)
        end
        return
    end

    local rows = {}
    repeat
        local row = {
            id = q:GetUInt32(0), copyId = q:GetUInt32(1), kind = q:GetString(2), entry = q:GetUInt32(3),
            itemGuid = q:GetUInt32(4), creatorGuid = q:GetUInt32(5), duration = q:GetInt32(6), charges = q:GetString(7),
            flags = q:GetUInt32(8), enchantments = q:GetString(9), randomPropertyId = q:GetInt16(10),
            sourceGuid = (not q:IsNull(11)) and q:GetUInt32(11) or nil, sourceName = q:GetString(12),
            sourceItemGuid = (not q:IsNull(13)) and q:GetUInt32(13) or nil, createdAt = q:GetString(14),
        }
        if row.sourceName == "" then
            row.sourceName = nil
        end
        row.missing, row.whereKey, row.whereValue = cc_locateMailedItem(row.itemGuid, targetGuid)
        table.insert(rows, row)
    until not q:NextRow()

    if mode == "list" then
        local missingCount = 0
        say("RESTORE_LIST_HEADER", targetName, targetGuid)
        if isOnline then
            say("RESTORE_LIST_ONLINE", targetName)
        end
        for _, row in ipairs(rows) do
            local where
            if row.whereValue ~= nil then
                where = cc_t(player, row.whereKey, row.whereValue)
            else
                where = cc_t(player, row.whereKey)
            end
            if row.missing then
                missingCount = missingCount + 1
                where = cc_t(player, "RESTORE_MISSING", where)
            end
            say("RESTORE_LIST_ROW", row.id, row.copyId, row.kind, row.createdAt, cc_itemLabel(player, row.entry), where)
        end
        say("RESTORE_LIST_FOOTER", #rows, missingCount, targetName)
        return
    end

    local toRestore = {}
    local skippedUnknown = 0
    for _, row in ipairs(rows) do
        if mode == "all" or row.missing then
            if cc_itemExists(row.entry) then
                table.insert(toRestore, row)
            else
                skippedUnknown = skippedUnknown + 1
            end
        end
    end
    if skippedUnknown > 0 then
        say("RESTORE_SKIPPED_UNKNOWN", skippedUnknown)
    end
    if #toRestore == 0 then
        abort("RESTORE_NOTHING", targetName, mode)
        return
    end

    -- keep the character offline while the mail and enchants are written (lifted by cc_finishRestore)
    if not kicked then
        Ban(1, targetName, 45, CC_BAN_REASON_RESTORE, admin.name)
    end

    -- the mail is in the target account's client language
    local mailLocale = 0
    local a = AuthDBQuery('SELECT `locale` FROM `account` WHERE `id` = '..targetAccount..' LIMIT 1;')
    if a ~= nil then
        mailLocale = a:GetUInt8(0)
    end

    local entries = {}
    for n, row in ipairs(toRestore) do
        entries[n] = row.entry
    end
    local guids = cc_sendItemMails(targetGuid, cc_tl(mailLocale, "MAIL_RESTORE_SUBJECT"),
        cc_tl(mailLocale, "MAIL_RESTORE_BODY", targetName, cc_mailSignature), entries)

    local job = { pairs = {}, attempts = 0, targetGuid = targetGuid, targetName = targetName,
        adminName = admin.name, adminGuid = admin.guid, mode = mode, kicked = kicked, clear = clear }
    for n, row in ipairs(toRestore) do
        if guids[n] ~= nil then
            table.insert(job.pairs, { row = row, newGuid = guids[n] })
        end
    end

    if #job.pairs == 0 then
        say("RESTORE_NONE_MAILED")
        cc_liftCarbonCopyBan(targetGuid)
        return
    end

    cc_restoreBusy[targetGuid] = true
    say("RESTORE_MAILING", #job.pairs, targetName, mode, targetName)
    CreateLuaEvent(function() cc_finishRestore(job) end, CC_POLL_MS, 1)
end

-- Revoke only takes items that are still unclaimed in the target's mailbox. Anything the player already took out
-- of the mail is left alone (and reported).
local CC_REVOKABLE = { LOC_MAILBOX = true }

-- Deletes an unclaimed mailed item: its mail_items row, the item, and the mail itself once it is empty.
local function cc_deleteMailedItem(itemGuid, targetGuid)
    local m = CharDBQuery('SELECT `mail_id` FROM `mail_items` WHERE `item_guid` = '..itemGuid..' AND `receiver` = '..targetGuid..' LIMIT 1;')
    if m == nil then
        return
    end
    local mailId = m:GetUInt32(0)
    CharDBQuery('DELETE FROM `mail_items` WHERE `item_guid` = '..itemGuid..' AND `receiver` = '..targetGuid..';')
    CharDBQuery('DELETE FROM `item_instance` WHERE `guid` = '..itemGuid..';')
    if CharDBQuery('SELECT 1 FROM `mail_items` WHERE `mail_id` = '..mailId..' LIMIT 1;') == nil then
        CharDBQuery('DELETE FROM `mail` WHERE `id` = '..mailId..' AND `money` = 0 AND `cod` = 0;')
        CharDBQuery('UPDATE `mail` SET `has_items` = 0 WHERE `id` = '..mailId..';')
    end
end

-- .carboncopy cleanup $days   (GM or console): delete mailed-items log rows that are $days days old or older
local function cc_execCleanupCommand(player, say, daysArg)
    local days = tonumber(daysArg)
    if days == nil or days < 1 or days ~= math.floor(days) then
        say("SYNTAX_CLEANUP")
        return
    end
    local admin = player and player:GetName() or "console"
    local count = cc_cleanupMailLog(days)
    say("CLEANUP_DONE", count, days)
    cc_logAdmin(admin, player and tonumber(tostring(player:GetGUID())) or nil, nil, nil, nil, CC_ACTION_GM_CLEANUP, nil, nil,
        CC_STATUS_SUCCESS, "Deleted "..count.." mailed-items log row(s) older than "..days.." day(s)")
end

local function cc_sendRevokeSyntax(say)
    say("SYNTAX_REVOKE_LIST")
    say("SYNTAX_REVOKE_ALL")
    say("SYNTAX_REVOKE_ID")
    say("SYNTAX_REVOKE_OPTIONS")
    say("SYNTAX_CLEANUP")
end

-- .carboncopy revoke $name [all|#logId] [copyId] [--kick] [--clear]   (GM or console)
-- Takes back CarbonCopy items that are still unclaimed in the mailbox. Without all/#logId it only lists what would
-- happen. Their log rows are marked revoked (restore skips them); with --clear they are deleted instead.
local function cc_execRevokeCommand(player, say, commandArray, startIdx, admin, kicked)
    admin = admin or { name = player and player:GetName() or "console", guid = player and tonumber(tostring(player:GetGUID())) or nil }

    if not cc_enableMailItemLog then
        say("RESTORE_LOG_DISABLED")
        return
    end
    if commandArray[startIdx] == nil then
        cc_sendRevokeSyntax(say)
        return
    end

    local targetName = cc_normalizeCharacterName(commandArray[startIdx])
    local execute, copyFilter, logId, kick, purge = false, nil, nil, false, false
    for n = startIdx + 1, startIdx + 5 do
        local token = commandArray[n] and string.lower(commandArray[n])
        if token == nil then
            break
        elseif token == "all" then
            execute = true
        elseif token == "--kick" then
            kick = true
        elseif token == "--clear" then
            purge = true
        elseif token:match("^#%d+$") then
            logId = tonumber(token:sub(2))
            execute = true
        elseif tonumber(token) ~= nil then
            copyFilter = tonumber(token)
        else
            cc_sendRevokeSyntax(say)
            return
        end
    end

    local q = CharDBQuery("SELECT `guid`, `online` FROM `characters` WHERE `name` = "..cc_sqlQuote(targetName).." LIMIT 1;")
    if q == nil then
        say("RESTORE_CHAR_NOT_FOUND", targetName)
        return
    end
    local targetGuid, targetOnline = q:GetUInt32(0), q:GetUInt8(1)
    local isOnline = targetOnline ~= 0 or GetPlayerByGUID(targetGuid) ~= nil

    local function finish()
        if kicked then
            cc_liftCarbonCopyBan(targetGuid)
        end
    end

    if execute then
        if cc_restoreBusy[targetGuid] then
            say("RESTORE_BUSY", targetName)
            finish()
            return
        end
        if cc_requireOffline(targetName, targetGuid, isOnline, kick, kicked, admin, say, CC_BAN_REASON_REVOKE,
            "REVOKE_ONLINE", "REVOKE_KICKING", "REVOKE_NOT_OFFLINE",
            function(notify) cc_execRevokeCommand(nil, notify, commandArray, startIdx, admin, true) end) then
            return
        end
    end

    local sql = 'SELECT `id`, `copy_id`, `kind`, `item_entry`, `item_guid`, DATE_FORMAT(`created_at`, "%Y-%m-%d %H:%i") '
        ..'FROM `'..Config.customDbName..'`.`'..cc_mailItemsTable..'` '
        ..'WHERE `target_guid` = '..targetGuid..' AND `superseded_by_id` IS NULL AND `revoked_at` IS NULL'
    if copyFilter ~= nil then
        sql = sql..' AND `copy_id` = '..copyFilter
    end
    if logId ~= nil then
        sql = sql..' AND `id` = '..logId
    end
    q = CharDBQuery(sql..' ORDER BY `id`;')
    if q == nil then
        if copyFilter ~= nil then
            say("RESTORE_NO_ITEMS_COPY", targetName, copyFilter)
        else
            say("RESTORE_NO_ITEMS", targetName)
        end
        finish()
        return
    end

    local remove, gone, skip = {}, {}, {}
    local rows = {}
    repeat
        local row = { id = q:GetUInt32(0), copyId = q:GetUInt32(1), kind = q:GetString(2), entry = q:GetUInt32(3),
            itemGuid = q:GetUInt32(4), createdAt = q:GetString(5) }
        local missing, whereKey, whereValue = cc_locateMailedItem(row.itemGuid, targetGuid)
        row.whereKey, row.whereValue = whereKey, whereValue
        if CC_REVOKABLE[whereKey] then
            row.action = "remove"
            table.insert(remove, row)
        elseif missing then
            row.action = "gone"
            table.insert(gone, row)
        else
            row.action = "skip"
            table.insert(skip, row)
        end
        table.insert(rows, row)
    until not q:NextRow()

    if not execute then
        say("REVOKE_LIST_HEADER", targetName, targetGuid)
        if isOnline then
            say("RESTORE_LIST_ONLINE", targetName)
        end
        for _, row in ipairs(rows) do
            local where
            if row.whereValue ~= nil then
                where = cc_t(player, row.whereKey, row.whereValue)
            else
                where = cc_t(player, row.whereKey)
            end
            local actionKey = (row.action == "remove" and "REVOKE_ROW_REMOVE") or (row.action == "gone" and "REVOKE_ROW_GONE") or "REVOKE_ROW_SKIP"
            say("RESTORE_LIST_ROW", row.id, row.copyId, row.kind, row.createdAt, cc_itemLabel(player, row.entry), cc_t(player, actionKey, where))
        end
        say("REVOKE_LIST_FOOTER", #remove, #gone, #skip, targetName)
        return
    end

    if #remove == 0 and #gone == 0 then
        say("REVOKE_NOTHING", targetName, #skip)
        finish()
        return
    end

    for _, row in ipairs(remove) do
        cc_deleteMailedItem(row.itemGuid, targetGuid)
    end

    -- the log rows of taken and already-gone items: deleted (purge) or marked revoked so restore leaves them alone
    local ids = {}
    for _, row in ipairs(remove) do table.insert(ids, row.id) end
    for _, row in ipairs(gone) do table.insert(ids, row.id) end
    local logTable = '`'..Config.customDbName..'`.`'..cc_mailItemsTable..'`'
    if purge then
        CharDBQuery('DELETE FROM '..logTable..' WHERE `id` IN ('..table.concat(ids, ',')..');')
    else
        CharDBQuery('UPDATE '..logTable..' SET `revoked_at` = NOW(), `revoked_by` = '..cc_sqlQuote(admin.name)
            ..' WHERE `id` IN ('..table.concat(ids, ',')..');')
    end

    finish()
    say("REVOKE_DONE", #remove, targetName, #gone, #skip, cc_t(player, purge and "REVOKE_LOG_DELETED" or "REVOKE_LOG_MARKED"))
    cc_logAdmin(admin.name, admin.guid, targetName, targetGuid, nil, CC_ACTION_GM_REVOKE, nil, nil, CC_STATUS_SUCCESS,
        "Revoked "..#remove.." item(s), "..#gone.." already gone, "..#skip.." skipped"..(purge and ", log rows deleted" or "")
        ..(kicked and ", kicked" or "")..(logId and (", log #"..logId) or "")..(copyFilter and (", copy "..copyFilter) or ""))
end

-- Pet numbers for copied hunter pets. The core hands out pet numbers from its own counter (MAX(id) at startup, then +1
-- per new pet), so MAX(id)+1 from Lua can be handed out again by the core before the next restart. Copied pets instead
-- count DOWN from CC_PET_ID_CEILING: the core's counter is far below that until a restart, and after a restart it starts
-- above the ceiling (MAX(id)+1), so the two can never meet. Stays below 2^31.
local CC_PET_ID_CEILING = 1073741824
local CC_PET_ID_RANGE = 100000000

local function cc_newPetId()
    local id = CC_PET_ID_CEILING
    local q = CharDBQuery('SELECT MIN(`id`) FROM `character_pet` WHERE `id` > '..(CC_PET_ID_CEILING - CC_PET_ID_RANGE)
        ..' AND `id` <= '..CC_PET_ID_CEILING..';')
    if q ~= nil and not q:IsNull(0) then
        id = q:GetUInt32(0) - 1
    end
    -- skip numbers that still have leftover rows
    while CharDBQuery('SELECT 1 FROM `character_pet` WHERE `id` = '..id..' LIMIT 1;') ~= nil
        or CharDBQuery('SELECT 1 FROM `pet_spell` WHERE `guid` = '..id..' LIMIT 1;') ~= nil do
        id = id - 1
    end
    return id
end

function cc_CopyCharacter(event, player, command, chatHandler)

    local commandArray = cc_splitString(command)
    local sourceName = player and player:GetName() or "console"
    local sourceGuid = player and tonumber(tostring(player:GetGUID())) or nil
    if commandArray[2] ~= nil then
        commandArray[2] = commandArray[2]:gsub("[\"';\\, ]", "")
        if commandArray[3] ~= nil then
            commandArray[3] = commandArray[3]:gsub("[\"';\\, ]", "")
        end
        if commandArray[4] ~= nil then
            commandArray[4] = commandArray[4]:gsub("[\"';\\, ]", "")
        end
        if commandArray[5] ~= nil then
            commandArray[5] = commandArray[5]:gsub("[\"';\\, ]", "")
        end
    end

    if commandArray[1] ~= "carboncopy" and commandArray[1] ~= "addcctickets" and commandArray[1] ~= "CCACCOUNTTICKETS" then
        return
    end

    if cc_scriptIsBusy ~= 0 and cc_copyStartedAt ~= nil and os.time() - cc_copyStartedAt > 120 then
        cc_copyFailed("watchdog", "copy still not finished after 120 seconds")
    end
    if cc_scriptIsBusy ~= 0 then
        local reason = cc_t(nil, "ERR_SERVER_BUSY")
        chatHandler:SendSysMessage(cc_t(player, "ERR_SERVER_BUSY"))
        PrintInfo("CarbonCopy user request failed because the script has a scheduled task.")
        if commandArray[1] == "carboncopy" and player ~= nil then
            cc_logPlayer(sourceName, sourceGuid, nil, nil, player:GetLevel(), nil, nil, CC_STATUS_FAILED, reason)
        end
        return false
    end

    if commandArray[1] == "carboncopy" then
        local ccSubCommandConsole = nil
        if commandArray[2] ~= nil then
            ccSubCommandConsole = string.lower(commandArray[2])
        end

        if player == nil and ccSubCommandConsole == "tickets" then
            if commandArray[3] == nil then
                chatHandler:SendSysMessage(cc_t(player, "SYNTAX_TICKETS_LOOKUP"))
                chatHandler:SendSysMessage(cc_t(player, "SYNTAX_TICKETS_ADD"))
                chatHandler:SendSysMessage(cc_t(player, "SYNTAX_TICKETS_REMOVE"))
                cc_resetVariables()
                return false
            end

            local ticketsAction = string.lower(commandArray[3])
            if ticketsAction == "add" then
                if commandArray[4] == nil or commandArray[5] == nil then
                    chatHandler:SendSysMessage(cc_t(player, "SYNTAX_TICKETS_ADD"))
                    cc_resetVariables()
                    return false
                end

                if tonumber(commandArray[5]) == nil or tonumber(commandArray[5]) > 1000 or tonumber(commandArray[5]) < 0 then
                    chatHandler:SendSysMessage(cc_t(player, "TICKETS_BAD_AMOUNT", ".carboncopy tickets add", commandArray[5]))
                    cc_resetVariables()
                    return false
                end

                local normalisedCharacterName = cc_normalizeCharacterName(commandArray[4])
                local Data_SQL = CharDBQuery("SELECT `account` FROM `characters` WHERE `name` = "..cc_sqlQuote(normalisedCharacterName).." LIMIT 1;")
                local accountId
                local oldTickets
                if Data_SQL ~= nil then
                    accountId = Data_SQL:GetUInt32(0)
                else
                    local reason = cc_t(nil, "TICKETS_PLAYER_NOT_FOUND").." "..cc_t(nil, "SYNTAX_TICKETS_ADD")
                    chatHandler:SendSysMessage(cc_t(player, "TICKETS_PLAYER_NOT_FOUND").." "..cc_t(player, "SYNTAX_TICKETS_ADD"))
                    cc_logAdmin("console", nil, normalisedCharacterName, nil, nil, CC_ACTION_GM_ADD, nil, nil, CC_STATUS_FAILED, reason)
                    cc_resetVariables()
                    return false
                end

                Data_SQL = CharDBQuery('SELECT `tickets` FROM `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` WHERE `account_id` = '..accountId..' LIMIT 1;')
                if Data_SQL ~= nil then
                    oldTickets = Data_SQL:GetUInt32(0)
                else
                    oldTickets = 0
                end

                if oldTickets >= 1000 or oldTickets < 0 then
                    local reason = cc_t(nil, "TICKETS_TOTAL_TOO_LARGE", commandArray[5], oldTickets)
                    chatHandler:SendSysMessage(cc_t(player, "TICKETS_TOTAL_TOO_LARGE", commandArray[5], oldTickets))
                    cc_logAdmin("console", nil, normalisedCharacterName, nil, nil, CC_ACTION_GM_ADD, oldTickets, oldTickets, CC_STATUS_FAILED, reason)
                    cc_resetVariables()
                    return false
                end

                CharDBQuery('DELETE FROM `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` WHERE `account_id` = '..accountId..';')
                CharDBQuery('INSERT INTO `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` VALUES ('..accountId..', '..commandArray[5] + oldTickets..', 0);')
                chatHandler:SendSysMessage(cc_t(player, "TICKETS_ADDED", cc_actor(player), ".carboncopy tickets add", commandArray[5], accountId, normalisedCharacterName))
                cc_logAdmin("console", nil, normalisedCharacterName, nil, nil, CC_ACTION_GM_ADD, oldTickets, oldTickets + tonumber(commandArray[5]), CC_STATUS_SUCCESS, "Console .carboncopy tickets add "..normalisedCharacterName.." "..commandArray[5])
                cc_resetVariables()
                return false
            end

            if ticketsAction == "remove" then
                if commandArray[4] == nil or commandArray[5] == nil then
                    chatHandler:SendSysMessage(cc_t(player, "SYNTAX_TICKETS_REMOVE"))
                    cc_resetVariables()
                    return false
                end

                if tonumber(commandArray[5]) == nil or tonumber(commandArray[5]) > 1000 or tonumber(commandArray[5]) < 0 then
                    chatHandler:SendSysMessage(cc_t(player, "TICKETS_BAD_AMOUNT", ".carboncopy tickets remove", commandArray[5]))
                    cc_resetVariables()
                    return false
                end

                local normalisedCharacterName = cc_normalizeCharacterName(commandArray[4])
                local Data_SQL = CharDBQuery("SELECT `account` FROM `characters` WHERE `name` = "..cc_sqlQuote(normalisedCharacterName).." LIMIT 1;")
                local accountId
                local oldTickets
                if Data_SQL ~= nil then
                    accountId = Data_SQL:GetUInt32(0)
                else
                    local reason = cc_t(nil, "TICKETS_PLAYER_NOT_FOUND").." "..cc_t(nil, "SYNTAX_TICKETS_REMOVE")
                    chatHandler:SendSysMessage(cc_t(player, "TICKETS_PLAYER_NOT_FOUND").." "..cc_t(player, "SYNTAX_TICKETS_REMOVE"))
                    cc_logAdmin("console", nil, normalisedCharacterName, nil, nil, CC_ACTION_GM_REMOVE, nil, nil, CC_STATUS_FAILED, reason)
                    cc_resetVariables()
                    return false
                end

                Data_SQL = CharDBQuery('SELECT `tickets` FROM `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` WHERE `account_id` = '..accountId..' LIMIT 1;')
                if Data_SQL ~= nil then
                    oldTickets = Data_SQL:GetUInt32(0)
                else
                    oldTickets = 0
                end

                if oldTickets <= 0 or oldTickets < tonumber(commandArray[5]) then
                    local reason = cc_t(nil, "TICKETS_NOT_ENOUGH_TO_REMOVE", commandArray[5], oldTickets)
                    chatHandler:SendSysMessage(cc_t(player, "TICKETS_NOT_ENOUGH_TO_REMOVE", commandArray[5], oldTickets))
                    cc_logAdmin("console", nil, normalisedCharacterName, nil, nil, CC_ACTION_GM_REMOVE, oldTickets, oldTickets, CC_STATUS_FAILED, reason)
                    cc_resetVariables()
                    return false
                end

                CharDBQuery('DELETE FROM `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` WHERE `account_id` = '..accountId..';')
                CharDBQuery('INSERT INTO `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` VALUES ('..accountId..', '..oldTickets - commandArray[5]..', 0);')
                chatHandler:SendSysMessage(cc_t(player, "TICKETS_REMOVED", cc_actor(player), ".carboncopy tickets remove", commandArray[5], accountId, normalisedCharacterName))
                cc_logAdmin("console", nil, normalisedCharacterName, nil, nil, CC_ACTION_GM_REMOVE, oldTickets, oldTickets - tonumber(commandArray[5]), CC_STATUS_SUCCESS, "Console .carboncopy tickets remove "..normalisedCharacterName.." "..commandArray[5])
                cc_resetVariables()
                return false
            end

            if ticketsAction ~= "lookup" then
                chatHandler:SendSysMessage(cc_t(player, "SYNTAX_TICKETS_LOOKUP"))
                chatHandler:SendSysMessage(cc_t(player, "SYNTAX_TICKETS_ADD"))
                chatHandler:SendSysMessage(cc_t(player, "SYNTAX_TICKETS_REMOVE"))
                cc_resetVariables()
                return false
            end

            local lookupNameArg = commandArray[4]
            if lookupNameArg == nil then
                chatHandler:SendSysMessage(cc_t(player, "SYNTAX_TICKETS_LOOKUP"))
                cc_resetVariables()
                return false
            end

            local lookupCharacterName = cc_normalizeCharacterName(lookupNameArg)
            local Data_SQL = CharDBQuery("SELECT `account` FROM `characters` WHERE `name` = "..cc_sqlQuote(lookupCharacterName).." LIMIT 1;")
            if Data_SQL == nil then
                local reason = cc_t(nil, "TICKETS_CHAR_NOT_FOUND")
                chatHandler:SendSysMessage(cc_t(player, "TICKETS_CHAR_NOT_FOUND"))
                cc_logAdmin("console", nil, lookupCharacterName, nil, nil, CC_ACTION_GM_LOOKUP, nil, nil, CC_STATUS_FAILED, reason)
                cc_resetVariables()
                return false
            end

            local lookupAccountId = Data_SQL:GetUInt32(0)
            Data_SQL = CharDBQuery('SELECT `tickets` FROM `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` WHERE `account_id` = '..lookupAccountId..' LIMIT 1;')
            local lookupTickets
            if Data_SQL ~= nil then
                lookupTickets = Data_SQL:GetUInt32(0)
            else
                lookupTickets = Config.freeTickets
            end

            chatHandler:SendSysMessage(cc_t(player, "TICKETS_LOOKUP_RESULT", lookupCharacterName, lookupAccountId, lookupTickets))
            cc_logAdmin("console", nil, lookupCharacterName, nil, nil, CC_ACTION_GM_LOOKUP, lookupTickets, lookupTickets, CC_STATUS_SUCCESS, "Console .carboncopy tickets lookup "..lookupCharacterName)
            cc_resetVariables()
            return false
        end

        if player == nil and ccSubCommandConsole == "restore" then
            cc_execRestoreCommand(nil, cc_chatSay(nil, chatHandler), commandArray, 3)
            cc_resetVariables()
            return false
        end

        if player == nil and ccSubCommandConsole == "cleanup" then
            cc_execCleanupCommand(nil, cc_chatSay(nil, chatHandler), commandArray[3])
            cc_resetVariables()
            return false
        end

        if player == nil and ccSubCommandConsole == "revoke" then
            cc_execRevokeCommand(nil, cc_chatSay(nil, chatHandler), commandArray, 3)
            cc_resetVariables()
            return false
        end

        if player == nil and ccSubCommandConsole == "logs" then
            cc_execLogsCommand(chatHandler, commandArray, 3)
            cc_resetVariables()
            return false
        end

        if player == nil and (ccSubCommandConsole == "config" or ccSubCommandConsole == "settings") then
            cc_execConfigCommand(chatHandler)
            cc_resetVariables()
            return false
        end

        -- console / SOAP: list the commands that work from here
        if player == nil and (ccSubCommandConsole == "help" or ccSubCommandConsole == "--help") then
            chatHandler:SendSysMessage(cc_t(player, "SYNTAX_TICKETS_LOOKUP"))
            chatHandler:SendSysMessage(cc_t(player, "SYNTAX_TICKETS_ADD"))
            chatHandler:SendSysMessage(cc_t(player, "SYNTAX_TICKETS_REMOVE"))
            chatHandler:SendSysMessage(cc_t(player, "SYNTAX_CONFIG"))
            chatHandler:SendSysMessage(cc_t(player, "SYNTAX_LOGS"))
            cc_sendRestoreSyntax(cc_chatSay(player, chatHandler))
                cc_sendRevokeSyntax(cc_chatSay(player, chatHandler))
            chatHandler:SendSysMessage(cc_t(player, "SYNTAX_ADDCCTICKETS")) -- Kept for Legacy / Compatibility
            chatHandler:SendSysMessage(cc_t(player, "SYNTAX_CCACCOUNTTICKETS"))
            chatHandler:SendSysMessage(cc_t(player, "CONSOLE_COPY_INGAME"))
            cc_resetVariables()
            return false
        end

        if player == nil then
            local reason = cc_t(nil, "ERR_COPY_FROM_CONSOLE")
            chatHandler:SendSysMessage(cc_t(player, "ERR_COPY_FROM_CONSOLE"))
            chatHandler:SendSysMessage(cc_t(player, "SYNTAX_ADDCCTICKETS")) -- Kept for Legacy / Compatibility
            return false
        end
        -- make sure the player is properly ranked
        if player:GetGMRank() < Config.minGMRankForCopy then
            local reason = cc_t(nil, "ERR_NO_PERMISSION")
            chatHandler:SendSysMessage(cc_t(player, "ERR_NO_PERMISSION"))
            cc_logPlayer(sourceName, sourceGuid, nil, nil, player:GetLevel(), nil, nil, CC_STATUS_FAILED, reason)
            cc_resetVariables()
            return false
        end

        -- provide syntax help (GM only, it lists the GM ticket/config/logs commands)
        if commandArray[2] == "help" then
            if player:GetGMRank() < Config.minGMRankForTickets then
                chatHandler:SendSysMessage(cc_t(player, "ERR_NO_PERMISSION"))
                cc_resetVariables()
                return false
            end
            chatHandler:SendSysMessage(cc_t(player, "SYNTAX_COPY"))
            chatHandler:SendSysMessage(cc_t(player, "SYNTAX_CONFIG"))
            chatHandler:SendSysMessage(cc_t(player, "SYNTAX_TICKETS_LOOKUP"))
            chatHandler:SendSysMessage(cc_t(player, "SYNTAX_TICKETS_ADD"))
            chatHandler:SendSysMessage(cc_t(player, "SYNTAX_TICKETS_REMOVE"))
            chatHandler:SendSysMessage(cc_t(player, "SYNTAX_LOGS"))
            if player:GetGMRank() >= cc_minGMRankForRestore then
                cc_sendRestoreSyntax(cc_chatSay(player, chatHandler))
                cc_sendRevokeSyntax(cc_chatSay(player, chatHandler))
            end
            cc_resetVariables()
            return false
        end

        -- print the available tickets
        local accountId = player:GetAccountId()
        local _ticketsAtEntrySQL = CharDBQuery('SELECT `tickets` FROM `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` WHERE `account_id` = '..accountId..' LIMIT 1;')
        local ticketsAtEntry = _ticketsAtEntrySQL ~= nil and _ticketsAtEntrySQL:GetUInt32(0) or Config.freeTickets
        _ticketsAtEntrySQL = nil
        if commandArray[2] == nil then
            local Data_SQL
            Data_SQL = CharDBQuery('SELECT `tickets` FROM `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` WHERE `account_id` = '..accountId..' LIMIT 1;');
            if Data_SQL  ~= nil then
                oldTickets = Data_SQL:GetUInt32(0)
                cc_logPlayer(sourceName, sourceGuid, nil, nil, player:GetLevel(), oldTickets, oldTickets, CC_STATUS_SUCCESS, "Ticket balance lookup")
            else
                oldTickets = Config.freeTickets
                CharDBExecute('REPLACE INTO `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` VALUES ('..accountId..', '..Config.freeTickets..', 0) ;')
                cc_logPlayer(sourceName, sourceGuid, nil, nil, player:GetLevel(), 0, Config.freeTickets, CC_STATUS_FREE_CONFIG_TICKET, "Free config ticket granted")
            end
            -- ticket cost list and map warning first, the most important lines last
            -- (closest to the chat input): balance, how to use it, and whether this character can be copied
            cc_sendTicketCosts(player, chatHandler)
            if not cc_has_value(cc_maps, player:GetMapId()) then
                chatHandler:SendSysMessage(cc_info(player, "WRONG_MAP"))
            end

            chatHandler:SendSysMessage(cc_info(player, "TICKETS", oldTickets))
            chatHandler:SendSysMessage(cc_info(player, "USAGE"))
            local level = player:GetLevel()
            local cost = cc_ticketCostForLevel(level)
            if level > Config.maxLevel or cost == nil then
                chatHandler:SendSysMessage(cc_info(player, "LEVEL_TOO_HIGH", level, Config.maxLevel))
            elseif oldTickets < cost then
                chatHandler:SendSysMessage(cc_info(player, "NOT_ENOUGH_TICKETS", level, cost, oldTickets))
            else
                chatHandler:SendSysMessage(cc_info(player, "ELIGIBLE", level, cost))
            end

            cc_resetVariables()
            return false
        end

        local ccSubCommand = string.lower(commandArray[2])
        if ccSubCommand == "config" or ccSubCommand == "settings" then
            if player:GetGMRank() < Config.minGMRankForTickets then
                chatHandler:SendSysMessage(cc_t(player, "ERR_NO_PERMISSION"))
                cc_resetVariables()
                return false
            end

            cc_execConfigCommand(chatHandler)
            cc_resetVariables()
            return false
        end

        if ccSubCommand == "tickets" then
            -- every tickets action (lookup / add / remove / syntax) is GM only
            if player:GetGMRank() < Config.minGMRankForTickets then
                chatHandler:SendSysMessage(cc_t(player, "ERR_NO_PERMISSION"))
                cc_resetVariables()
                return false
            end

            if commandArray[3] == nil then
                chatHandler:SendSysMessage(cc_t(player, "SYNTAX_TICKETS_LOOKUP"))
                chatHandler:SendSysMessage(cc_t(player, "SYNTAX_TICKETS_ADD"))
                chatHandler:SendSysMessage(cc_t(player, "SYNTAX_TICKETS_REMOVE"))
                cc_resetVariables()
                return false
            end

            local ticketsAction = string.lower(commandArray[3])
            if ticketsAction == "add" then
                if player:GetGMRank() < Config.minGMRankForTickets then
                    chatHandler:SendSysMessage(cc_t(player, "ERR_NO_PERMISSION"))
                    cc_resetVariables()
                    return false
                end

                if commandArray[4] == nil or commandArray[5] == nil then
                    chatHandler:SendSysMessage(cc_t(player, "SYNTAX_TICKETS_ADD"))
                    cc_resetVariables()
                    return false
                end

                if tonumber(commandArray[5]) == nil or tonumber(commandArray[5]) > 1000 or tonumber(commandArray[5]) < 0 then
                    chatHandler:SendSysMessage(cc_t(player, "TICKETS_BAD_AMOUNT", ".carboncopy tickets add", commandArray[5]))
                    cc_resetVariables()
                    return false
                end

                local normalisedCharacterName = cc_normalizeCharacterName(commandArray[4])
                local Data_SQL = CharDBQuery("SELECT `account` FROM `characters` WHERE `name` = "..cc_sqlQuote(normalisedCharacterName).." LIMIT 1;")
                local addAccountId
                local oldTickets
                if Data_SQL ~= nil then
                    addAccountId = Data_SQL:GetUInt32(0)
                else
                    local reason = cc_t(nil, "TICKETS_PLAYER_NOT_FOUND").." "..cc_t(nil, "SYNTAX_TICKETS_ADD")
                    chatHandler:SendSysMessage(cc_t(player, "TICKETS_PLAYER_NOT_FOUND").." "..cc_t(player, "SYNTAX_TICKETS_ADD"))
                    cc_logAdmin(sourceName, sourceGuid, normalisedCharacterName, nil, nil, CC_ACTION_GM_ADD, nil, nil, CC_STATUS_FAILED, reason)
                    cc_resetVariables()
                    return false
                end

                Data_SQL = CharDBQuery('SELECT `tickets` FROM `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` WHERE `account_id` = '..addAccountId..' LIMIT 1;')
                if Data_SQL ~= nil then
                    oldTickets = Data_SQL:GetUInt32(0)
                else
                    oldTickets = 0
                end

                if oldTickets >= 1000 or oldTickets < 0 then
                    local reason = cc_t(nil, "TICKETS_TOTAL_TOO_LARGE", commandArray[5], oldTickets)
                    chatHandler:SendSysMessage(cc_t(player, "TICKETS_TOTAL_TOO_LARGE", commandArray[5], oldTickets))
                    cc_logAdmin(sourceName, sourceGuid, normalisedCharacterName, nil, nil, CC_ACTION_GM_ADD, oldTickets, oldTickets, CC_STATUS_FAILED, reason)
                    cc_resetVariables()
                    return false
                end

                CharDBQuery('DELETE FROM `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` WHERE `account_id` = '..addAccountId..';')
                CharDBQuery('INSERT INTO `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` VALUES ('..addAccountId..', '..commandArray[5] + oldTickets..', 0);')
                chatHandler:SendSysMessage(cc_t(player, "TICKETS_ADDED", cc_actor(player), ".carboncopy tickets add", commandArray[5], addAccountId, normalisedCharacterName))
                cc_logAdmin(sourceName, sourceGuid, normalisedCharacterName, nil, nil, CC_ACTION_GM_ADD, oldTickets, oldTickets + tonumber(commandArray[5]), CC_STATUS_SUCCESS, "GM .carboncopy tickets add")
                cc_resetVariables()
                return false
            end

            if ticketsAction == "remove" then
                if player:GetGMRank() < Config.minGMRankForTickets then
                    chatHandler:SendSysMessage(cc_t(player, "ERR_NO_PERMISSION"))
                    cc_resetVariables()
                    return false
                end

                if commandArray[4] == nil or commandArray[5] == nil then
                    chatHandler:SendSysMessage(cc_t(player, "SYNTAX_TICKETS_REMOVE"))
                    cc_resetVariables()
                    return false
                end

                if tonumber(commandArray[5]) == nil or tonumber(commandArray[5]) > 1000 or tonumber(commandArray[5]) < 0 then
                    chatHandler:SendSysMessage(cc_t(player, "TICKETS_BAD_AMOUNT", ".carboncopy tickets remove", commandArray[5]))
                    cc_resetVariables()
                    return false
                end

                local normalisedCharacterName = cc_normalizeCharacterName(commandArray[4])
                local Data_SQL = CharDBQuery("SELECT `account` FROM `characters` WHERE `name` = "..cc_sqlQuote(normalisedCharacterName).." LIMIT 1;")
                local removeAccountId
                local oldTickets
                if Data_SQL ~= nil then
                    removeAccountId = Data_SQL:GetUInt32(0)
                else
                    local reason = cc_t(nil, "TICKETS_PLAYER_NOT_FOUND").." "..cc_t(nil, "SYNTAX_TICKETS_REMOVE")
                    chatHandler:SendSysMessage(cc_t(player, "TICKETS_PLAYER_NOT_FOUND").." "..cc_t(player, "SYNTAX_TICKETS_REMOVE"))
                    cc_logAdmin(sourceName, sourceGuid, normalisedCharacterName, nil, nil, CC_ACTION_GM_REMOVE, nil, nil, CC_STATUS_FAILED, reason)
                    cc_resetVariables()
                    return false
                end

                Data_SQL = CharDBQuery('SELECT `tickets` FROM `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` WHERE `account_id` = '..removeAccountId..' LIMIT 1;')
                if Data_SQL ~= nil then
                    oldTickets = Data_SQL:GetUInt32(0)
                else
                    oldTickets = 0
                end

                if oldTickets <= 0 or oldTickets < tonumber(commandArray[5]) then
                    local reason = cc_t(nil, "TICKETS_NOT_ENOUGH_TO_REMOVE", commandArray[5], oldTickets)
                    chatHandler:SendSysMessage(cc_t(player, "TICKETS_NOT_ENOUGH_TO_REMOVE", commandArray[5], oldTickets))
                    cc_logAdmin(sourceName, sourceGuid, normalisedCharacterName, nil, nil, CC_ACTION_GM_REMOVE, oldTickets, oldTickets, CC_STATUS_FAILED, reason)
                    cc_resetVariables()
                    return false
                end

                CharDBQuery('DELETE FROM `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` WHERE `account_id` = '..removeAccountId..';')
                CharDBQuery('INSERT INTO `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` VALUES ('..removeAccountId..', '..oldTickets - commandArray[5]..', 0);')
                chatHandler:SendSysMessage(cc_t(player, "TICKETS_REMOVED", cc_actor(player), ".carboncopy tickets remove", commandArray[5], removeAccountId, normalisedCharacterName))
                cc_logAdmin(sourceName, sourceGuid, normalisedCharacterName, nil, nil, CC_ACTION_GM_REMOVE, oldTickets, oldTickets - tonumber(commandArray[5]), CC_STATUS_SUCCESS, "GM .carboncopy tickets remove")
                cc_resetVariables()
                return false
            end

            if ticketsAction ~= "lookup" then
                chatHandler:SendSysMessage(cc_t(player, "SYNTAX_TICKETS_LOOKUP"))
                chatHandler:SendSysMessage(cc_t(player, "SYNTAX_TICKETS_ADD"))
                chatHandler:SendSysMessage(cc_t(player, "SYNTAX_TICKETS_REMOVE"))
                cc_resetVariables()
                return false
            end

            local lookupNameArg = commandArray[4]
            if lookupNameArg == nil then
                chatHandler:SendSysMessage(cc_t(player, "SYNTAX_TICKETS_LOOKUP"))
                cc_resetVariables()
                return false
            end

            local lookupCharacterName = cc_normalizeCharacterName(lookupNameArg)
            local Data_SQL = CharDBQuery("SELECT `account` FROM `characters` WHERE `name` = "..cc_sqlQuote(lookupCharacterName).." LIMIT 1;")
            if Data_SQL == nil then
                local reason = cc_t(nil, "TICKETS_CHAR_NOT_FOUND")
                chatHandler:SendSysMessage(cc_t(player, "TICKETS_CHAR_NOT_FOUND"))
                cc_logAdmin(sourceName, sourceGuid, lookupCharacterName, nil, nil, CC_ACTION_GM_LOOKUP, nil, nil, CC_STATUS_FAILED, reason)
                cc_resetVariables()
                return false
            end

            local lookupAccountId = Data_SQL:GetUInt32(0)
            Data_SQL = CharDBQuery('SELECT `tickets` FROM `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` WHERE `account_id` = '..lookupAccountId..' LIMIT 1;')
            local lookupTickets
            if Data_SQL ~= nil then
                lookupTickets = Data_SQL:GetUInt32(0)
            else
                lookupTickets = Config.freeTickets
            end

            chatHandler:SendSysMessage(cc_t(player, "TICKETS_LOOKUP_RESULT", lookupCharacterName, lookupAccountId, lookupTickets))
            cc_logAdmin(sourceName, sourceGuid, lookupCharacterName, nil, nil, CC_ACTION_GM_LOOKUP, lookupTickets, lookupTickets, CC_STATUS_SUCCESS, "GM .carboncopy tickets lookup")
            cc_resetVariables()
            return false
        end

        if ccSubCommand == "logs" then
            if player:GetGMRank() < Config.minGMRankForTickets then
                chatHandler:SendSysMessage(cc_t(player, "ERR_NO_PERMISSION"))
                cc_resetVariables()
                return false
            end
            cc_execLogsCommand(chatHandler, commandArray, 3)
            cc_resetVariables()
            return false
        end

        if ccSubCommand == "restore" then
            if player:GetGMRank() < cc_minGMRankForRestore then
                chatHandler:SendSysMessage(cc_t(player, "ERR_NO_PERMISSION"))
                cc_resetVariables()
                return false
            end
            cc_execRestoreCommand(player, cc_chatSay(player, chatHandler), commandArray, 3)
            cc_resetVariables()
            return false
        end

        if ccSubCommand == "cleanup" then
            if player:GetGMRank() < cc_minGMRankForRestore then
                chatHandler:SendSysMessage(cc_t(player, "ERR_NO_PERMISSION"))
                cc_resetVariables()
                return false
            end
            cc_execCleanupCommand(player, cc_chatSay(player, chatHandler), commandArray[3])
            cc_resetVariables()
            return false
        end

        if ccSubCommand == "revoke" then
            if player:GetGMRank() < cc_minGMRankForRestore then
                chatHandler:SendSysMessage(cc_t(player, "ERR_NO_PERMISSION"))
                cc_resetVariables()
                return false
            end
            cc_execRevokeCommand(player, cc_chatSay(player, chatHandler), commandArray, 3)
            cc_resetVariables()
            return false
        end

        -- check maxLevel
        if player:GetLevel() > Config.maxLevel then
            local reason = cc_t(nil, "ERR_COPY_LEVEL_TOO_HIGH", Config.maxLevel)
            chatHandler:SendSysMessage(cc_t(player, "ERR_COPY_LEVEL_TOO_HIGH", Config.maxLevel))
            cc_logPlayer(sourceName, sourceGuid, nil, nil, player:GetLevel(), ticketsAtEntry, ticketsAtEntry, CC_STATUS_FAILED, reason)
            cc_resetVariables()
            return false
        end

        cc_playerGUID = tostring(player:GetGUID())
        cc_playerGUID = tonumber(cc_playerGUID)
        local targetName = cc_normalizeCharacterName(commandArray[2])

        --check for target character to be on same account
        local Data_SQL = CharDBQuery("SELECT `account` FROM `characters` WHERE `name` = "..cc_sqlQuote(targetName).." LIMIT 1;");
        if Data_SQL == nil then
            local reason = cc_t(nil, "ERR_COPY_NAME_NOT_FOUND")
            chatHandler:SendSysMessage(cc_t(player, "ERR_COPY_NAME_NOT_FOUND"))
            cc_logPlayer(sourceName, sourceGuid, targetName, nil, player:GetLevel(), ticketsAtEntry, ticketsAtEntry, CC_STATUS_FAILED, reason)
            cc_resetVariables()
            return false
        end
        local targetAccountId = Data_SQL:GetUInt32(0)
        Data_SQL = nil
        if targetAccountId ~= accountId then
            local reason = cc_t(nil, "ERR_COPY_NOT_SAME_ACCOUNT")
            chatHandler:SendSysMessage(cc_t(player, "ERR_COPY_NOT_SAME_ACCOUNT"))
            cc_logPlayer(sourceName, sourceGuid, targetName, nil, player:GetLevel(), ticketsAtEntry, ticketsAtEntry, CC_STATUS_FAILED, reason)
            cc_resetVariables()
            return false
        end

        local Data_SQL = CharDBQuery("SELECT `guid` FROM `characters` WHERE `name` = "..cc_sqlQuote(targetName).." LIMIT 1;");
        local newCharacter
        if Data_SQL ~= nil then
            newCharacter = Data_SQL:GetUInt32(0)
       	else
            local reason = cc_t(nil, "ERR_COPY_NAME_NOT_FOUND")
            chatHandler:SendSysMessage(cc_t(player, "ERR_COPY_NAME_NOT_FOUND"))
            cc_logPlayer(sourceName, sourceGuid, targetName, nil, player:GetLevel(), ticketsAtEntry, ticketsAtEntry, CC_STATUS_FAILED, reason)
            cc_resetVariables()
            return false
        end
        Data_SQL = nil

        --check for available tickets
        local Data_SQL = CharDBQuery('SELECT `tickets` FROM `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` WHERE `account_id` = '..accountId..';');
        local availableTickets
        local requiredTickets
        if Data_SQL ~= nil then
            availableTickets = Data_SQL:GetUInt32(0)
            Data_SQL = nil
        else
            CharDBExecute('REPLACE INTO `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` VALUES ('..accountId..', '..Config.freeTickets..', 0) ;')
            availableTickets = Config.freeTickets
        end

        if Config.ticketCost == "single" then
            if availableTickets ~= nil and availableTickets <= 0 then
                local reason = cc_t(nil, "ERR_COPY_NOT_ENOUGH_TICKETS")
                chatHandler:SendSysMessage(cc_t(player, "ERR_COPY_NOT_ENOUGH_TICKETS"))
                cc_logPlayer(sourceName, sourceGuid, targetName, newCharacter, player:GetLevel(), availableTickets, availableTickets, CC_STATUS_FAILED, reason)
                cc_resetVariables()
                return false
            end
            requiredTickets = 1
        elseif Config.ticketCost == "level" then
            -- cost of the first ticket_Cost bracket at or above the level; nil if no bracket covers it
            -- (the old loop here never ended in that case and froze the server)
            requiredTickets = cc_ticketCostForLevel(player:GetLevel())
            if requiredTickets == nil then
                local reason = cc_t(nil, "ERR_COPY_LEVEL_TOO_HIGH", Config.maxLevel)
                chatHandler:SendSysMessage(cc_t(player, "ERR_COPY_LEVEL_TOO_HIGH", Config.maxLevel))
                cc_logPlayer(sourceName, sourceGuid, targetName, newCharacter, player:GetLevel(), availableTickets, availableTickets, CC_STATUS_FAILED, reason.." (no ticket_Cost bracket for this level)")
                PrintError("CarbonCopy: no ticket_Cost bracket covers level "..player:GetLevel()..". Add one in CarbonCopy_Config.lua.")
                cc_resetVariables()
                return false
            end
            if availableTickets ~= nil and availableTickets <= 0 then
                local reason = cc_t(nil, "ERR_COPY_NOT_ENOUGH_TICKETS")
                chatHandler:SendSysMessage(cc_t(player, "ERR_COPY_NOT_ENOUGH_TICKETS"))
                cc_logPlayer(sourceName, sourceGuid, targetName, newCharacter, player:GetLevel(), availableTickets, availableTickets, CC_STATUS_FAILED, reason)
                cc_resetVariables()
                return false
            end
            if availableTickets < requiredTickets then
                local reason = cc_t(nil, "ERR_COPY_NOT_ENOUGH_TICKETS")
                chatHandler:SendSysMessage(cc_t(player, "ERR_COPY_NOT_ENOUGH_TICKETS"))
                cc_logPlayer(sourceName, sourceGuid, targetName, newCharacter, player:GetLevel(), availableTickets, availableTickets, CC_STATUS_FAILED, reason)
                cc_resetVariables()
                return false
            end
        else
            PrintError("Unhandled exception in CarbonCopy. Config.ticketCost is neither set to \"single\" nor \"level\".")
            chatHandler:SendSysMessage(cc_t(player, "ERR_SERVER_BUSY"))
            cc_resetVariables()
            return false
        end

        --check for target character to be same class/race
        local Data_SQL = CharDBQuery('SELECT `race`, `class` FROM `characters` WHERE `guid` = '..cc_playerGUID..' LIMIT 1;');
        local sourceRace = Data_SQL:GetUInt8(0)
        local sourceClass = Data_SQL:GetUInt8(1)
        Data_SQL = nil

        local Data_SQL = CharDBQuery('SELECT `race`, `class` FROM `characters` WHERE `guid` = '..newCharacter..' LIMIT 1;');
        local targetRace = Data_SQL:GetUInt8(0)
        local targetClass = Data_SQL:GetUInt8(1)
        Data_SQL = nil

        if sourceRace ~= targetRace then
            local reason = cc_t(nil, "ERR_COPY_NOT_SAME_RACE")
            chatHandler:SendSysMessage(cc_t(player, "ERR_COPY_NOT_SAME_RACE"))
            cc_logPlayer(sourceName, sourceGuid, targetName, newCharacter, player:GetLevel(), availableTickets, availableTickets, CC_STATUS_FAILED, reason)
            cc_resetVariables()
            return false
        end
        if sourceClass ~= targetClass then
            local reason = cc_t(nil, "ERR_COPY_NOT_SAME_CLASS")
            chatHandler:SendSysMessage(cc_t(player, "ERR_COPY_NOT_SAME_CLASS"))
            cc_logPlayer(sourceName, sourceGuid, targetName, newCharacter, player:GetLevel(), availableTickets, availableTickets, CC_STATUS_FAILED, reason)
            cc_resetVariables()
            return false
        end

        -- check if target character wasn't logged in
        local cc_cinematic
        local Data_SQL = CharDBQuery('SELECT cinematic FROM characters WHERE guid = '..newCharacter..';');
        if Data_SQL ~= nil then
            cc_cinematic = Data_SQL:GetUInt16(0)
            if cc_cinematic == 1 then
                local reason = cc_t(nil, "ERR_COPY_ALREADY_LOGGED_IN")
                chatHandler:SendSysMessage(cc_t(player, "ERR_COPY_ALREADY_LOGGED_IN"))
                cc_logPlayer(sourceName, sourceGuid, targetName, newCharacter, player:GetLevel(), availableTickets, availableTickets, CC_STATUS_FAILED, reason)
                cc_cinematic = nil
                cc_resetVariables()
                return false
            end
        else
            PrintError("Unhandled exception in CarbonCopy. Could not read characters.cinematic from cc_playerGUID "..newCharacter..".")
        end

        -- check if target character is logged in currently in case cinematic wasnt already written to db
        local cc_online
        local Data_SQL = CharDBQuery('SELECT online FROM characters WHERE guid = '..newCharacter..';');
        if Data_SQL ~= nil then
            cc_online = Data_SQL:GetUInt16(0)
            if cc_online == 1 then
                local reason = cc_t(nil, "ERR_COPY_ALREADY_LOGGED_IN")
                chatHandler:SendSysMessage(cc_t(player, "ERR_COPY_ALREADY_LOGGED_IN"))
                cc_logPlayer(sourceName, sourceGuid, targetName, newCharacter, player:GetLevel(), availableTickets, availableTickets, CC_STATUS_FAILED, reason)
                cc_online = nil
                cc_resetVariables()
                return false
            end
        else
            PrintError("Unhandled exception in CarbonCopy. Could not read characters.online from cc_playerGUID "..newCharacter..".")
        end

        -- check source characters location
        local cc_mapId
        cc_mapId = player:GetMapId()
        if not cc_has_value(cc_maps, cc_mapId) then
            local reason = cc_t(nil, "ERR_COPY_WRONG_MAP")
            chatHandler:SendSysMessage(cc_t(player, "ERR_COPY_WRONG_MAP"))
            cc_logPlayer(sourceName, sourceGuid, targetName, newCharacter, player:GetLevel(), availableTickets, availableTickets, CC_STATUS_FAILED, reason)
            cc_resetVariables()
            return false
        end

        -------------- COPY SCRIPT STARTS HERE ---------------------
        --set Global variable to prevent simultaneous action and lock the target.
        --The ban is lifted by cc_fixItems as soon as the copy is done; 45s is only the fallback if that never runs.
        Ban(1, targetName, 45, CC_BAN_REASON_COPY, "CarbonCopy" )
        cc_scriptIsBusy = 1
        cc_newCharacter = newCharacter
        cc_newCharacterName = targetName
        cc_copyTicketsBefore = availableTickets
        cc_copyTicketsAfter = availableTickets - requiredTickets
        cc_copySourceName = sourceName
        cc_copySourceLevel = player:GetLevel()

        -- save the source character to db to prevent recent changes from being not applied
        player:SaveToDB()

        --fetch all required variables before 1st yield
        cc_playerString = player:GetClassAsString(0)
        cc_logPlayer(sourceName, sourceGuid, targetName, cc_newCharacter, player:GetLevel(), availableTickets, availableTickets - requiredTickets, CC_STATUS_SUCCESS, "Copy started")
        PrintInfo("1) The player with GUID "..cc_playerGUID.." has succesfully initiated the .carboncopy command. Target character: "..cc_newCharacter);
        chatHandler:SendSysMessage(cc_t(player, "COPY_STARTED", requiredTickets, availableTickets - requiredTickets))
        -- Display English and Italian (as Italian doesn't have a locale in Wrath), plus the player's own locale
        local locale = player:GetDbcLocale()
        chatHandler:SendSysMessage(cc_tl(0, "COPY_STAY"))
        chatHandler:SendSysMessage(cc_tl(0, "COPY_STAY_ITALIAN"))
        if locale ~= 0 and L.COPY_STAY[locale] ~= nil then
            chatHandler:SendSysMessage(cc_tl(locale, "COPY_STAY"))
        end
        -- mails for the new character use the copying player's locale (same account, same client)
        cc_copyLocale = locale

        -- what a failed copy needs to refund and unlock (see cc_copyFailed)
        cc_copyAccountId = accountId
        cc_copyCharged = 0
        cc_copyMailed = false
        cc_copyStartedAt = os.time()

        -- resumes the copy once a second until it is finished (cc_resumeSubRoutine removes the event)
        cc_eventId = CreateLuaEvent(cc_resumeSubRoutine, 1000, 0)

        cc_subRoutine = coroutine.create(function ()

        -- deduct tickets
        if Config.ticketCost == "single" then
            requiredTickets = 1
        end
        CharDBQuery('UPDATE `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` SET tickets = tickets -'..requiredTickets..' WHERE `account_id` = '..accountId..';');
        cc_copyCharged = requiredTickets

        -- delete TempTables
        cc_deleteTempTables(cc_playerGUID)

        -- Copy characters table
        local QueryString
        QueryString = 'UPDATE `characters` AS t1 '
        QueryString = QueryString..'INNER JOIN `characters` AS t2 ON t2.guid = '..cc_playerGUID..' '
        QueryString = QueryString..'SET t1.level = t2.level, t1.xp = t2.xp, t1.taximask = t2.taximask, '
        QueryString = QueryString..'t1.leveltime = t2.leveltime, t1.stable_slots = t2.stable_slots, t1.health = t2.health, '
        QueryString = QueryString..'t1.power1 = t2.power1, t1.power2 = t2.power2, t1.power3 = t2.power3, t1.power4 = t2.power4, '
        QueryString = QueryString..'t1.power5 = t2.power5, t1.power6 = t2.power6, t1.power7 = t2.power7, t1.talentGroupsCount = t2.talentGroupsCount, '
        QueryString = QueryString..'t1.activeTalentGroup = t2.activeTalentGroup, '
        QueryString = QueryString..'t1.exploredZones = t2.exploredZones WHERE t1.guid = '..cc_newCharacter..';'
        local Data_SQL = CharDBQuery(QueryString);
        QueryString = nil
        Data_SQL = nil
        local Data_SQL = CharDBQuery('UPDATE characters SET cinematic = 1 WHERE guid = '..cc_newCharacter..';');

        -- start the new character in its faction's capital (Config.teleportToCapital)
        if cc_teleportToCapital then
            local pos = cc_capitalForRace(sourceRace)
            if pos ~= nil then
                CharDBQuery('UPDATE `characters` SET `map` = '..tonumber(pos.map)..', `zone` = '..tonumber(pos.zone)
                    ..', `position_x` = '..tonumber(pos.x)..', `position_y` = '..tonumber(pos.y)..', `position_z` = '..tonumber(pos.z)
                    ..', `orientation` = '..tonumber(pos.o or 0)..', `instance_id` = 0, `instance_mode_mask` = 0'
                    ..', `trans_x` = 0, `trans_y` = 0, `trans_z` = 0, `trans_o` = 0, `transguid` = 0'
                    ..' WHERE `guid` = '..cc_newCharacter..';')
            end
        end

        coroutine.yield()
        -- Copy achivements level ups 10, 20, 30, 40, 50, 60, 70 or 80 if they exist and use carboncopy sucess timestamp when it was "obtained".
        local level_achievements = {6, 7, 8, 9, 10, 11, 12, 13}
        local achievement_list = table.concat(level_achievements, ",")
        local Data_SQL = CharDBQuery('DELETE FROM character_achievement WHERE guid = '..cc_newCharacter..' AND achievement IN ('..achievement_list..');')
        local Data_SQL = CharDBQuery('INSERT INTO character_achievement (guid, achievement, date) SELECT '..cc_newCharacter..', achievement, UNIX_TIMESTAMP() FROM character_achievement WHERE guid = '..cc_playerGUID..' AND achievement IN ('..achievement_list..');')
        Data_SQL = nil

        coroutine.yield()
        -- Hearthstone bind point: the capital (Config.homebindToCapital) or the source's, Booty Bay if that isn't valid
        local bind
        if cc_homebindToCapital then
            bind = cc_capitalForRace(sourceRace)
        else
            local hb = CharDBQuery('SELECT mapId, zoneId, posX, posY, posZ FROM character_homebind WHERE guid = '..cc_playerGUID..' LIMIT 1;')
            if hb ~= nil then
                bind = { map = hb:GetUInt16(0), zone = hb:GetUInt16(1), x = hb:GetFloat(2), y = hb:GetFloat(3), z = hb:GetFloat(4) }
            end
        end
        local bindValid = bind ~= nil and cc_has_value(CC_CONTINENTS, tonumber(bind.map)) and (tonumber(bind.zone) or 0) ~= 0
            and not (tonumber(bind.x) == 0 and tonumber(bind.y) == 0 and tonumber(bind.z) == 0)
        if not bindValid then
            PrintInfo("CarbonCopy: no valid bind point for character "..cc_newCharacter..", using the neutral one (capitalPositions.neutral).")
            bind = cc_capitalPositions.neutral
        end
        CharDBQuery('DELETE FROM character_homebind WHERE guid = '..cc_newCharacter..';')
        CharDBQuery('INSERT INTO character_homebind (guid, mapId, zoneId, posX, posY, posZ) VALUES ('..cc_newCharacter..', '
            ..tonumber(bind.map)..', '..tonumber(bind.zone)..', '..tonumber(bind.x)..', '..tonumber(bind.y)..', '..tonumber(bind.z)..');')

        -- Copy character_pet and totems
        if cc_playerString == "Hunter" then
            -- the active pet first (slot 0), then a dismissed one (100), then the stabled ones; oldest first within each
            local Data_SQL = CharDBQuery('SELECT id FROM character_pet WHERE owner = '..cc_playerGUID
                ..' ORDER BY CASE WHEN slot = 0 THEN 0 WHEN slot = 100 THEN 1 ELSE 2 END, id LIMIT 1;');
            if Data_SQL ~= nil then
                cc_playerPetId = Data_SQL:GetUInt32(0)
                Data_SQL = nil

                local cc_targetPetId = cc_newPetId()

                local Data_SQL = CharDBQuery('DELETE FROM character_pet WHERE owner = '..cc_newCharacter..';')
                local Data_SQL = CharDBQuery('CREATE TEMPORARY TABLE tempPet'..cc_playerGUID..' LIKE character_pet;')
                local Data_SQL = CharDBQuery('INSERT INTO tempPet'..cc_playerGUID..' SELECT * FROM character_pet WHERE id = '..cc_playerPetId..';')
                local Data_SQL = CharDBQuery('UPDATE tempPet'..cc_playerGUID..' SET id = '..cc_targetPetId..', slot = 0, owner = '..cc_newCharacter..';')
                local Data_SQL = CharDBQuery('INSERT INTO character_pet SELECT * FROM tempPet'..cc_playerGUID..';')
                local Data_SQL = CharDBQuery('DROP TABLE IF EXISTS tempPet'..cc_playerGUID..';')

                QueryString = nil
                Data_SQL = nil

                local Data_SQL = CharDBQuery('DELETE FROM pet_spell WHERE guid = '..cc_targetPetId..';')
                local Data_SQL = CharDBQuery('CREATE TEMPORARY TABLE tempPet_spell'..cc_playerGUID..' LIKE pet_spell;')
                local Data_SQL = CharDBQuery('INSERT INTO tempPet_spell'..cc_playerGUID..' SELECT * FROM pet_spell WHERE guid = '..cc_playerPetId..';')
                local Data_SQL = CharDBQuery('UPDATE tempPet_spell'..cc_playerGUID..' SET guid = '..cc_targetPetId..' WHERE guid = '..cc_playerPetId..';')
                local Data_SQL = CharDBQuery('INSERT INTO pet_spell SELECT * FROM tempPet_spell'..cc_playerGUID..';')
                local Data_SQL = CharDBQuery('DROP TABLE IF EXISTS tempPet_spell'..cc_playerGUID..';')
                QueryString = nil
                Data_SQL = nil
            end
        elseif cc_playerString == "Shaman" then
            -- only the totems the source character owns, in their own mail
            -- (earth, fire, water, air, Totem of the Earthen Ring)
            local totems = {}
            for _, entry in ipairs({5175, 5176, 5177, 5178, 46978}) do
                if CharDBQuery('SELECT 1 FROM item_instance WHERE owner_guid = '..cc_playerGUID..' AND itemEntry = '..entry..' LIMIT 1;') ~= nil then
                    table.insert(totems, entry)
                end
            end
            local realTotems = #totems
            if cc_emptySlotFiller > 0 and realTotems > 0 then
                while #totems < 5 do
                    table.insert(totems, cc_emptySlotFiller)
                end
            end
            cc_totemMailGuids = {}
            cc_totemItemGuids = {}
            if #totems > 0 then
                cc_copyMailed = true
                local guids = cc_sendItemMails(cc_newCharacter, cc_tl(cc_copyLocale, "MAIL_TOTEMS_SUBJECT"),
                    (cc_legacyMailText and ("Hello "..targetName..cc_legacyMailText) or cc_tl(cc_copyLocale, "MAIL_TOTEMS_BODY", targetName, cc_mailSignature)), totems)
                for n = 1, #totems do
                    if guids[n] ~= nil then
                        table.insert(cc_totemMailGuids, guids[n])
                        if n <= realTotems then
                            table.insert(cc_totemItemGuids, guids[n])
                        end
                    end
                end
            end
        end

        coroutine.yield()
        --Copy quests
        local Data_SQL = CharDBQuery('DELETE FROM character_queststatus_rewarded WHERE guid = '..cc_newCharacter..';')
        local Data_SQL = CharDBQuery('CREATE TEMPORARY TABLE tempQuest'..cc_playerGUID..' LIKE character_queststatus_rewarded;')
        local Data_SQL = CharDBQuery('INSERT INTO tempQuest'..cc_playerGUID..' SELECT * FROM character_queststatus_rewarded WHERE guid = '..cc_playerGUID..';')
        local Data_SQL = CharDBQuery('UPDATE tempQuest'..cc_playerGUID..' SET guid = '..cc_newCharacter..' WHERE guid = '..cc_playerGUID..';')
        local Data_SQL = CharDBQuery('INSERT INTO character_queststatus_rewarded SELECT * FROM tempQuest'..cc_playerGUID..';')
        local Data_SQL = CharDBQuery('DROP TABLE IF EXISTS tempQuest'..cc_playerGUID..';')
        Data_SQL = nil

        coroutine.yield()
        --Copy reputation
        local Data_SQL = CharDBQuery('DELETE FROM character_reputation WHERE guid = '..cc_newCharacter..';')
        local Data_SQL = CharDBQuery('CREATE TEMPORARY TABLE tempReputation'..cc_playerGUID..' LIKE character_reputation;')
        local Data_SQL = CharDBQuery('INSERT INTO tempReputation'..cc_playerGUID..' SELECT * FROM character_reputation WHERE guid = '..cc_playerGUID..';')
        local Data_SQL = CharDBQuery('UPDATE tempReputation'..cc_playerGUID..' SET guid = '..cc_newCharacter..' WHERE guid = '..cc_playerGUID..';')
        local Data_SQL = CharDBQuery('INSERT INTO character_reputation SELECT * FROM tempReputation'..cc_playerGUID..';')
        local Data_SQL = CharDBQuery('DROP TABLE IF EXISTS tempReputation'..cc_playerGUID..';')
        Data_SQL = nil

        coroutine.yield()
        --Copy skills
        local Data_SQL = CharDBQuery('DELETE FROM character_skills WHERE guid = '..cc_newCharacter..';')
        local Data_SQL = CharDBQuery('CREATE TEMPORARY TABLE tempSkills'..cc_playerGUID..' LIKE character_skills;')
        local Data_SQL = CharDBQuery('INSERT INTO tempSkills'..cc_playerGUID..' SELECT * FROM character_skills WHERE guid = '..cc_playerGUID..';')
        local Data_SQL = CharDBQuery('UPDATE tempSkills'..cc_playerGUID..' SET guid = '..cc_newCharacter..' WHERE guid = '..cc_playerGUID..';')
        local Data_SQL = CharDBQuery('INSERT INTO character_skills SELECT * FROM tempSkills'..cc_playerGUID..';')
        local Data_SQL = CharDBQuery('DROP TABLE IF EXISTS tempSkills'..cc_playerGUID..';')
        Data_SQL = nil

        coroutine.yield()
        --Copy spells
        local Data_SQL = CharDBQuery('DELETE FROM character_spell WHERE guid = '..cc_newCharacter..';')
        local Data_SQL = CharDBQuery('CREATE TEMPORARY TABLE tempSpell'..cc_playerGUID..' LIKE character_spell;')
        local Data_SQL = CharDBQuery('INSERT INTO tempSpell'..cc_playerGUID..' SELECT * FROM character_spell WHERE guid = '..cc_playerGUID..';')
        local Data_SQL = CharDBQuery('UPDATE tempSpell'..cc_playerGUID..' SET guid = '..cc_newCharacter..' WHERE guid = '..cc_playerGUID..';')
        local Data_SQL = CharDBQuery('INSERT INTO character_spell SELECT * FROM tempSpell'..cc_playerGUID..';')
        local Data_SQL = CharDBQuery('DROP TABLE IF EXISTS tempSpell'..cc_playerGUID..';')
        Data_SQL = nil

        coroutine.yield()
        --Copy talents
        local Data_SQL = CharDBQuery('DELETE FROM character_talent WHERE guid = '..cc_newCharacter..';')
        local Data_SQL = CharDBQuery('CREATE TEMPORARY TABLE tempTalent'..cc_playerGUID..' LIKE character_talent;')
        local Data_SQL = CharDBQuery('INSERT INTO tempTalent'..cc_playerGUID..' SELECT * FROM character_talent WHERE guid = '..cc_playerGUID..';')
        local Data_SQL = CharDBQuery('UPDATE tempTalent'..cc_playerGUID..' SET guid = '..cc_newCharacter..' WHERE guid = '..cc_playerGUID..';')
        local Data_SQL = CharDBQuery('INSERT INTO character_talent SELECT * FROM tempTalent'..cc_playerGUID..';')
        local Data_SQL = CharDBQuery('DROP TABLE IF EXISTS tempTalent'..cc_playerGUID..';')
        Data_SQL = nil

        -- Config.resetTalentsAfterCopy: the core resets the active spec at first login (AT_LOGIN_RESET_TALENTS, it
        -- also removes the talent spells properly). The other spec is cleared here: its talents and the spells only
        -- it had are dropped, and talents/spells shared by both specs are left to the active spec only.
        if cc_resetTalentsAfterCopy then
            local sg = CharDBQuery('SELECT activeTalentGroup FROM characters WHERE guid = '..cc_newCharacter..' LIMIT 1;')
            local activeMask = 1
            if sg ~= nil then
                activeMask = (sg:GetUInt8(0) == 1) and 2 or 1   -- spec 1 = mask 1, spec 2 = mask 2
            end
            CharDBQuery('DELETE FROM character_talent WHERE guid = '..cc_newCharacter..' AND (specMask & '..activeMask..') = 0;')
            CharDBQuery('UPDATE character_talent SET specMask = (specMask & '..activeMask..') WHERE guid = '..cc_newCharacter..';')
            CharDBQuery('DELETE FROM character_spell WHERE guid = '..cc_newCharacter..' AND specMask <> 255 AND (specMask & '..activeMask..') = 0;')
            CharDBQuery('UPDATE character_spell SET specMask = (specMask & '..activeMask..') WHERE guid = '..cc_newCharacter
                ..' AND specMask <> 255 AND specMask <> '..activeMask..';')
            CharDBQuery('UPDATE characters SET at_login = (at_login | 4) WHERE guid = '..cc_newCharacter..';')
        end

        coroutine.yield()
        --Copy glyphs
        local Data_SQL = CharDBQuery('DELETE FROM character_glyphs WHERE guid = '..cc_newCharacter..';')
        local Data_SQL = CharDBQuery('CREATE TEMPORARY TABLE tempGlyphs'..cc_playerGUID..' LIKE character_glyphs;')
        local Data_SQL = CharDBQuery('INSERT INTO tempGlyphs'..cc_playerGUID..' SELECT * FROM character_glyphs WHERE guid = '..cc_playerGUID..';')
        local Data_SQL = CharDBQuery('UPDATE tempGlyphs'..cc_playerGUID..' SET guid = '..cc_newCharacter..' WHERE guid = '..cc_playerGUID..';')
        local Data_SQL = CharDBQuery('INSERT INTO character_glyphs SELECT * FROM tempGlyphs'..cc_playerGUID..';')
        local Data_SQL = CharDBQuery('DROP TABLE IF EXISTS tempGlyphs'..cc_playerGUID..';')
        Data_SQL = nil

        coroutine.yield()
        --Copy actions
        local Data_SQL = CharDBQuery('DELETE FROM character_action WHERE guid = '..cc_newCharacter..';')
        local Data_SQL = CharDBQuery('CREATE TEMPORARY TABLE tempAction'..cc_playerGUID..' LIKE character_action;')
        local Data_SQL = CharDBQuery('INSERT INTO tempAction'..cc_playerGUID..' SELECT * FROM character_action WHERE guid = '..cc_playerGUID..';')
        local Data_SQL = CharDBQuery('UPDATE tempAction'..cc_playerGUID..' SET guid = '..cc_newCharacter..' WHERE guid = '..cc_playerGUID..';')
        local Data_SQL = CharDBQuery('INSERT INTO character_action SELECT * FROM tempAction'..cc_playerGUID..';')
        local Data_SQL = CharDBQuery('DROP TABLE IF EXISTS tempAction'..cc_playerGUID..';')
        Data_SQL = nil

        coroutine.yield()
        --Copy items
        if not Config.keepStartingItems then
            -- delete everything the new character has except one Hearthstone (if it has one at all)
            local hearthstone = CharDBQuery('SELECT guid FROM item_instance WHERE owner_guid = '..cc_newCharacter..' AND itemEntry = 6948 LIMIT 1;')
            if hearthstone ~= nil then
                local homeStone = hearthstone:GetUInt32(0)
                CharDBQuery('DELETE FROM item_instance WHERE owner_guid = '..cc_newCharacter..' AND guid != '..homeStone..';')
                CharDBQuery('DELETE FROM character_inventory WHERE guid = '..cc_newCharacter..' AND item != '..homeStone..';')
            else
                CharDBQuery('DELETE FROM item_instance WHERE owner_guid = '..cc_newCharacter..';')
                CharDBQuery('DELETE FROM character_inventory WHERE guid = '..cc_newCharacter..';')
            end
        end
        Data_SQL = nil

        -- equipped items (slots 0-18), only the slots that hold something
        local Data_SQL = CharDBQuery('SELECT ci.item, ii.itemEntry FROM character_inventory AS ci '
            ..'INNER JOIN item_instance AS ii ON ii.guid = ci.item '
            ..'WHERE ci.guid = '..cc_playerGUID..' AND ci.bag = 0 AND ci.slot <= 18 ORDER BY ci.slot;')
        local gearEntries = {}
        if Data_SQL ~= nil then
            repeat
                local oldGuid, entry = Data_SQL:GetUInt32(0), Data_SQL:GetUInt32(1)
                if cc_itemExists(entry) then
                    table.insert(cc_oldItemGuids, oldGuid)
                    table.insert(gearEntries, entry)
                else
                    PrintError("CarbonCopy: item entry "..entry.." (item guid "..oldGuid..") no longer exists, not copied.")
                end
            until not Data_SQL:NextRow()
        end
        Data_SQL = nil

        -- optional legacy filler (Config.emptySlotFiller) so every mail is full, like the old script did
        local mailEntries = {}
        for n, entry in ipairs(gearEntries) do
            mailEntries[n] = entry
        end
        -- a new character without a Hearthstone gets one with the gear (not logged, it isn't a copied item)
        if CharDBQuery('SELECT 1 FROM item_instance WHERE owner_guid = '..cc_newCharacter..' AND itemEntry = 6948 LIMIT 1;') == nil then
            table.insert(mailEntries, 6948)
        end
        if cc_emptySlotFiller > 0 and #mailEntries > 0 then
            local fillTo = #mailEntries <= 12 and 12 or 18
            while #mailEntries < fillTo do
                table.insert(mailEntries, cc_emptySlotFiller)
            end
        end
        if #mailEntries > 0 then
            cc_copyMailed = true
            local guids = cc_sendItemMails(cc_newCharacter, cc_tl(cc_copyLocale, "MAIL_GEAR_SUBJECT"),
                (cc_legacyMailText and ("Hello "..targetName..cc_legacyMailText) or cc_tl(cc_copyLocale, "MAIL_GEAR_BODY", targetName, cc_mailSignature)), mailEntries)
            for n = 1, #mailEntries do
                cc_newItemGuids[n] = guids[n]
            end
        end
        CreateLuaEvent(cc_fixItems, CC_POLL_MS, 1) -- as soon as the mails are saved (cc_fixItems polls)
        cc_deleteTempTables(cc_playerGUID)

        -- the "copy complete" message and the success log are written by cc_fixItems, once the items are really done
        cc_resetVariables()

        return false
        end)

        return false

    elseif commandArray[1] == "addcctickets" then
        -- make sure the player is properly ranked
        local accountId
        local oldTickets
        local Data_SQL
        if player ~= nil then
            if player:GetGMRank() < Config.minGMRankForTickets then
                cc_resetVariables()
                return false
            end
            if commandArray[2] == "help" then
                chatHandler:SendSysMessage(cc_t(player, "SYNTAX_ADDCCTICKETS")) -- Kept for Legacy / Compatibility
                cc_resetVariables()
                return false
            end
            if commandArray[2] == nil or commandArray[3] == nil then
                chatHandler:SendSysMessage(cc_t(player, "SYNTAX_ADDCCTICKETS")) -- Kept for Legacy / Compatibility
                cc_resetVariables()
                return false
            end

            if tonumber(commandArray[3]) > 1000 or tonumber(commandArray[3]) < 0 then
                chatHandler:SendSysMessage(cc_t(player, "TICKETS_BAD_AMOUNT", ".addcctickets", commandArray[3]))
                cc_resetVariables()
                return false
            end

            local normalisedCharacterName = cc_normalizeCharacterName(commandArray[2])
            Data_SQL = CharDBQuery("SELECT `account` FROM `characters` WHERE `name` = "..cc_sqlQuote(normalisedCharacterName).." LIMIT 1;");
            if Data_SQL ~= nil then
                accountId = Data_SQL:GetUInt32(0)
            else
                chatHandler:SendSysMessage(cc_t(player, "TICKETS_PLAYER_NOT_FOUND").." "..cc_t(player, "SYNTAX_ADDCCTICKETS"))
                cc_resetVariables()
                return false
            end
            Data_SQL = nil
            local Data_SQL
            Data_SQL = CharDBQuery('SELECT `tickets` FROM `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` WHERE `account_id` = '..accountId..' LIMIT 1;');
            if Data_SQL  ~= nil then
                oldTickets = Data_SQL:GetUInt32(0)
            else
                oldTickets = 0
            end
            Data_SQL = nil

            if oldTickets >= 1000 or oldTickets < 0 then
                chatHandler:SendSysMessage(cc_t(player, "TICKETS_TOTAL_TOO_LARGE", commandArray[3], oldTickets))
                cc_resetVariables()
                return false
            end

            -- the `allow_copy_from_id` column is hardcoded to 0 for now. Only copies to the same account are possible.
            local Data_SQL
            Data_SQL = CharDBQuery('DELETE FROM `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` WHERE `account_id` = '..accountId..';');
            Data_SQL = CharDBQuery('INSERT INTO `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` VALUES ('..accountId..', '..commandArray[3] + oldTickets..', 0);');
            Data_SQL = nil
            chatHandler:SendSysMessage(cc_t(player, "TICKETS_ADDED", cc_actor(player), ".addcctickets", commandArray[3], accountId, normalisedCharacterName))
            cc_logAdmin(sourceName, sourceGuid, normalisedCharacterName, nil, nil, CC_ACTION_GM_ADD, oldTickets, oldTickets + tonumber(commandArray[3]), CC_STATUS_SUCCESS, "GM .addcctickets")
            cc_resetVariables()
            return false
        else
            --player is nil, must be the console. no need to check gm rank and print to console only. not chat
            if commandArray[2] == "help" then
                chatHandler:SendSysMessage(cc_t(player, "SYNTAX_ADDCCTICKETS")) -- Kept for Legacy / Compatibility
                cc_resetVariables()
                return false
            end
            if commandArray[2] == nil or commandArray[3] == nil then
                chatHandler:SendSysMessage(cc_t(player, "SYNTAX_ADDCCTICKETS")) -- Kept for Legacy / Compatibility
                cc_resetVariables()
                return false
            end

            if tonumber(commandArray[3]) > 1000 or tonumber(commandArray[3]) < 0 then
                chatHandler:SendSysMessage(cc_t(player, "TICKETS_BAD_AMOUNT", ".addcctickets", commandArray[3]))
                cc_resetVariables()
                return false
            end

            local normalisedCharacterName = cc_normalizeCharacterName(commandArray[2])
            Data_SQL = CharDBQuery("SELECT `account` FROM `characters` WHERE `name` = "..cc_sqlQuote(normalisedCharacterName).." LIMIT 1;");
            if Data_SQL ~= nil then
                accountId = Data_SQL:GetUInt32(0)
            else
                chatHandler:SendSysMessage(cc_t(player, "TICKETS_PLAYER_NOT_FOUND").." "..cc_t(player, "SYNTAX_ADDCCTICKETS"))
                cc_resetVariables()
                return false
            end
            Data_SQL = nil
            local Data_SQL
            Data_SQL = CharDBQuery('SELECT `tickets` FROM `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` WHERE `account_id` = '..accountId..' LIMIT 1;');
            if Data_SQL  ~= nil then
                oldTickets = Data_SQL:GetUInt32(0)
            else
                oldTickets = 0
            end
            Data_SQL = nil

            if oldTickets >= 1000 or oldTickets < 0 then
                chatHandler:SendSysMessage(cc_t(player, "TICKETS_TOTAL_TOO_LARGE", commandArray[3], oldTickets))
                cc_resetVariables()
                return false
            end

            -- the `allow_copy_from_id` column is hardcoded to 0 for now. Only copies to the same account are possible.
            local Data_SQL
            Data_SQL = CharDBQuery('DELETE FROM `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` WHERE `account_id` = '..accountId..';');
            Data_SQL = CharDBQuery('INSERT INTO `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` VALUES ('..accountId..', '..commandArray[3] + oldTickets..', 0);');
            Data_SQL = nil
            chatHandler:SendSysMessage(cc_t(player, "TICKETS_ADDED", cc_actor(player), ".addcctickets", commandArray[3], accountId, normalisedCharacterName))
            cc_logAdmin("console", nil, normalisedCharacterName, nil, nil, CC_ACTION_GM_ADD, oldTickets, oldTickets + tonumber(commandArray[3]), CC_STATUS_SUCCESS, "Console .addcctickets")
            cc_resetVariables()
            return false
        end
    -- command for SOAP interface to send to worldserver console, granting tickets. Syntax: CCACCOUNTTICKETS $accountName $amount
    elseif commandArray[1] == "CCACCOUNTTICKETS" and commandArray[2] ~= nil and commandArray[3] ~= nil and player == nil then
        local Data_SQL
        Data_SQL = AuthDBQuery("SELECT `id` FROM `account` WHERE `username` = "..cc_sqlQuote(commandArray[2])..";")
        if Data_SQL == nil then
            PrintError("CCACCOUNTTICKETS to "..commandArray[2].." has failed.")
            cc_logAdmin("console", nil, commandArray[2], nil, nil, CC_ACTION_GM_ADD, nil, nil, CC_STATUS_FAILED, "CCACCOUNTTICKETS account not found")
            cc_resetVariables()
            return false
        else
            accountId = Data_SQL:GetUInt32(0)
        end

        if tonumber(commandArray[3]) > 1000 or tonumber(commandArray[3]) < 0 then
            chatHandler:SendSysMessage(cc_t(player, "TICKETS_BAD_AMOUNT", ".CCACCOUNTTICKETS", commandArray[3]))
            cc_resetVariables()
            return false
        end

        Data_SQL = CharDBQuery('SELECT `tickets` FROM `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` WHERE `account_id` = '..accountId..' LIMIT 1;');
        if Data_SQL  ~= nil then
            oldTickets = Data_SQL:GetUInt32(0)
        else
            oldTickets = 0
        end

        if oldTickets >= 1000 or oldTickets < 0 then
            chatHandler:SendSysMessage(cc_t(player, "TICKETS_TOTAL_TOO_LARGE", commandArray[3], oldTickets))
            cc_logAdmin("console", nil, commandArray[2], nil, nil, CC_ACTION_GM_ADD, oldTickets, oldTickets, CC_STATUS_FAILED, "CCACCOUNTTICKETS total exceeds max")
            cc_resetVariables()
            return false
        end

        CharDBExecute('REPLACE INTO `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` VALUES ('..accountId..', '..commandArray[3] + oldTickets..', 0) ;')
        cc_logAdmin("console", nil, commandArray[2], nil, nil, CC_ACTION_GM_ADD, oldTickets, oldTickets + tonumber(commandArray[3]), CC_STATUS_SUCCESS, "CCACCOUNTTICKETS success")
        cc_resetVariables()
        return false
    elseif player ~= nil then
        -- CCACCOUNTTICKETS is SOAP / console only: stay silent for players, like .addcctickets
        return false
    else
        chatHandler:SendSysMessage(cc_t(player, "SYNTAX_CCACCOUNTTICKETS"))
        return false
    end
end

-- A copy step failed with a Lua/DB error. Refunds the tickets when nothing has been mailed yet (and lets the player
-- try again, the copy overwrites everything it touches), unlocks the new character, releases the lock, tells the player.
function cc_copyFailed(stage, err)
    -- refund / unlock / log / tell the player; protected so the lock below is released even if this part fails
    local cleanupOk, cleanupErr = pcall(function()
        PrintError("CarbonCopy: copy to character "..tostring(cc_newCharacter).." failed during "..stage..": "..tostring(err))
        local refunded = 0
        if cc_copyAccountId ~= nil and (cc_copyCharged or 0) > 0 and not cc_copyMailed then
            CharDBQuery('UPDATE `'..Config.customDbName..'`.`'..cc_carboncopyTable..'` SET tickets = tickets + '..cc_copyCharged
                ..' WHERE `account_id` = '..cc_copyAccountId..';')
            refunded = cc_copyCharged
            if cc_newCharacter ~= nil and cc_newCharacter ~= 0 then
                CharDBQuery('UPDATE `characters` SET `cinematic` = 0 WHERE `guid` = '..cc_newCharacter..';')
            end
        end
        if cc_newCharacter ~= nil and cc_newCharacter ~= 0 then
            cc_liftCarbonCopyBan(cc_newCharacter)
        end
        if cc_playerGUID ~= nil then
            cc_deleteTempTables(cc_playerGUID)
        end

        cc_logPlayer(cc_copySourceName or cc_characterNameByGuid(cc_playerGUID), cc_playerGUID, cc_newCharacterName,
            (cc_newCharacter ~= 0) and cc_newCharacter or nil, cc_copySourceLevel,
            cc_copyTicketsBefore, refunded > 0 and cc_copyTicketsBefore or cc_copyTicketsAfter, CC_STATUS_FAILED,
            "Copy failed during "..stage..(refunded > 0 and ", "..refunded.." ticket(s) refunded" or ", items already mailed, no refund")
            ..": "..string.sub(tostring(err), 1, 150))

        local copyingPlayer = cc_playerGUID ~= nil and GetPlayerByGUID(cc_playerGUID) or nil
        if copyingPlayer ~= nil then
            if refunded > 0 then
                copyingPlayer:SendBroadcastMessage(cc_t(copyingPlayer, "COPY_FAILED_REFUNDED", refunded))
            else
                copyingPlayer:SendBroadcastMessage(cc_t(copyingPlayer, "COPY_FAILED_CONTACT_GM"))
            end
        end

    end)
    if not cleanupOk then
        PrintError("CarbonCopy: cleanup after the failed copy also failed: "..tostring(cleanupErr))
    end

    cc_subRoutine = nil
    cc_newCharacter = 0
    cc_newCharacterName = nil
    cc_copyTicketsBefore = nil
    cc_copyTicketsAfter = nil
    cc_copySourceName = nil
    cc_copySourceLevel = nil
    cc_copyAccountId = nil
    cc_copyCharged = 0
    cc_copyMailed = false
    cc_copyStartedAt = nil
    cc_oldItemGuids = {}
    cc_newItemGuids = {}
    cc_totemMailGuids = {}
    cc_totemItemGuids = {}
    cc_fixItemsAttempts = 0
    cc_scriptIsBusy = 0
    cc_playerGUID = nil
end

-- Finishes the copy (enchants, mail expiry, logs, unlock); any error goes to cc_copyFailed instead of leaving the lock on.
function cc_fixItems()
    local ok, err = pcall(cc_fixItemsStep)
    if not ok then
        cc_copyFailed("item fix", err)
    end
end

function cc_fixItemsStep()
    local n
    local Data_SQL

    -- SendMail commits asynchronously; wait (up to pollIntervalMs x pollMaxAttempts) until the mailed items are in the DB
    local mailedGuids = {}
    for _, guid in pairs(cc_newItemGuids) do
        table.insert(mailedGuids, guid)
    end
    for _, guid in ipairs(cc_totemMailGuids) do
        table.insert(mailedGuids, guid)
    end
    if not cc_mailItemsCommitted(mailedGuids) and cc_fixItemsAttempts < CC_POLL_MAX then
        cc_fixItemsAttempts = cc_fixItemsAttempts + 1
        CreateLuaEvent(cc_fixItems, CC_POLL_MS, 1)
        return
    end
    cc_fixItemsAttempts = 0

    for n,_ in ipairs(cc_oldItemGuids) do
      if cc_newItemGuids[n] ~= nil then
        QueryString = 'UPDATE `item_instance` AS t1 '
        QueryString = QueryString..'INNER JOIN `item_instance` AS t2 ON t2.guid = '..cc_oldItemGuids[n]..' '
        QueryString = QueryString..'SET t1.owner_guid = '..cc_newCharacter..', t1.creatorGuid = t2.creatorGuid, '
        QueryString = QueryString..'t1.duration = t2.duration, t1.charges = t2.charges, t1.flags = '..cc_copyFlagsSql('t2.flags')..', '
        QueryString = QueryString..'t1.enchantments = t2.enchantments, t1.randomPropertyId = t2.randomPropertyId '
        QueryString = QueryString..'WHERE t1.guid = '..cc_newItemGuids[n]..';'
        Data_SQL = CharDBQuery(QueryString);
      end
    end

    -- Copy equipment sets with remapped item GUIDs
    if Config.copyEquipmentSets then
        local guidMap = {}
        for n,_ in ipairs(cc_oldItemGuids) do
            if cc_oldItemGuids[n] ~= nil and cc_newItemGuids[n] ~= nil then
                guidMap[cc_oldItemGuids[n]] = cc_newItemGuids[n]
            end
        end

        CharDBQuery('DELETE FROM `character_equipmentsets` WHERE `guid` = '..cc_newCharacter..';')

        local sets_SQL = CharDBQuery('SELECT `setindex`, `name`, `iconname`, `ignore_mask`, `item0`, `item1`, `item2`, `item3`, `item4`, `item5`, `item6`, `item7`, `item8`, `item9`, `item10`, `item11`, `item12`, `item13`, `item14`, `item15`, `item16`, `item17`, `item18` FROM `character_equipmentsets` WHERE `guid` = '..cc_playerGUID..';')
        if sets_SQL ~= nil then
            repeat
                local setindex    = sets_SQL:GetUInt8(0)
                local name        = sets_SQL:GetString(1):gsub("'", "''")
                local iconname    = sets_SQL:GetString(2):gsub("'", "''")
                local ignore_mask = sets_SQL:GetUInt32(3)
                local items = {}
                for i = 0, 18 do
                    local oldGuid = sets_SQL:GetUInt32(4 + i)
                    items[i] = guidMap[oldGuid] or 0
                end
                CharDBQuery('INSERT INTO `character_equipmentsets` (`guid`, `setindex`, `name`, `iconname`, `ignore_mask`, `item0`, `item1`, `item2`, `item3`, `item4`, `item5`, `item6`, `item7`, `item8`, `item9`, `item10`, `item11`, `item12`, `item13`, `item14`, `item15`, `item16`, `item17`, `item18`) VALUES ('
                    ..cc_newCharacter..', '..setindex..', \''..name..'\',' ..' \''..iconname..'\', '..ignore_mask..', '
                    ..items[0]..', '..items[1]..', '..items[2]..', '..items[3]..', '..items[4]..', '
                    ..items[5]..', '..items[6]..', '..items[7]..', '..items[8]..', '..items[9]..', '
                    ..items[10]..', '..items[11]..', '..items[12]..', '..items[13]..', '..items[14]..', '
                    ..items[15]..', '..items[16]..', '..items[17]..', '..items[18]..');')
            until not sets_SQL:NextRow()
        end
    end

    -- keep the copy mails in the mailbox (core default is 30 days, after which GM mail is deleted with its items)
    cc_extendMailForItems(cc_newCharacter, mailedGuids)

    -- log what was mailed (with enchants/gems/suffix) so an admin can restore it later
    if cc_enableMailItemLog then
        local copyId = cc_nextCopyId()
        local sourceName = cc_characterNameByGuid(cc_playerGUID)
        local targetName = cc_newCharacterName or cc_characterNameByGuid(cc_newCharacter)
        for n,_ in ipairs(cc_oldItemGuids) do
            cc_logMailedItem(copyId, "copy", cc_playerGUID, sourceName, cc_newCharacter, targetName, cc_oldItemGuids[n], cc_newItemGuids[n], nil, nil)
        end
        for _, guid in ipairs(cc_totemItemGuids) do
            cc_logMailedItem(copyId, "copy", cc_playerGUID, sourceName, cc_newCharacter, targetName, nil, guid, nil, nil)
        end
    end
    cc_totemMailGuids = {}
    cc_totemItemGuids = {}

    -- everything is written: unlock the new character and log the success
    cc_liftCarbonCopyBan(cc_newCharacter)
    local doneTargetName = cc_newCharacterName or cc_characterNameByGuid(cc_newCharacter) or tostring(cc_newCharacter)
    cc_logPlayer(cc_copySourceName or cc_characterNameByGuid(cc_playerGUID), cc_playerGUID, doneTargetName, cc_newCharacter,
        cc_copySourceLevel, cc_copyTicketsBefore, cc_copyTicketsAfter, CC_STATUS_SUCCESS, "Character copied")

    -- tell the player a few seconds later, so the unlock has settled before they log out and pick the new character
    local doneSourceGuid = cc_playerGUID
    CreateLuaEvent(function()
        local copyingPlayer = doneSourceGuid ~= nil and GetPlayerByGUID(doneSourceGuid) or nil
        if copyingPlayer ~= nil then
            copyingPlayer:SendBroadcastMessage(cc_t(copyingPlayer, "COPY_COMPLETE", doneTargetName))
        end
    end, cc_doneMessageDelay * 1000, 1)

    PrintInfo("2) Item enchants/gems copied for new character with GUID "..cc_newCharacter);
    cc_copySourceName = nil
    cc_copySourceLevel = nil
    cc_copyAccountId = nil
    cc_copyCharged = 0
    cc_copyMailed = false
    cc_copyStartedAt = nil
    cc_newCharacter = 0
    cc_newCharacterName = nil
    cc_copyTicketsBefore = nil
    cc_copyTicketsAfter = nil
    cc_oldItemGuids = {}
    cc_newItemGuids = {}
    cc_scriptIsBusy = 0
    cc_playerGUID = nil
end

function cc_resetVariables()
    Data_SQL = nil
    Data_SQL2 = nil
    ItemCounter = nil
    targetName = nil
    QueryString = nil
    cc_playerPetId = nil
    cc_targetPetId = nil
    item_id = nil
    homeStone = nil
    cc_playerString = nil
    cc_cinematic = nil
    commandArray = nil
    availableTickets = nil
    newItemGuid = nil
end

function cc_deleteTempTables(cc_GUID)
    CharDBQuery('DROP TABLE IF EXISTS tempQuest'..cc_GUID..';')
    CharDBQuery('DROP TABLE IF EXISTS tempPet'..cc_GUID..';')
    CharDBQuery('DROP TABLE IF EXISTS tempPet_spell'..cc_GUID..';')
    CharDBQuery('DROP TABLE IF EXISTS tempReputation'..cc_GUID..';')
    CharDBQuery('DROP TABLE IF EXISTS tempSkills'..cc_GUID..';')
    CharDBQuery('DROP TABLE IF EXISTS tempSpell'..cc_GUID..';')
    CharDBQuery('DROP TABLE IF EXISTS tempTalent'..cc_GUID..';')
    CharDBQuery('DROP TABLE IF EXISTS tempGlyphs'..cc_GUID..';')
    CharDBQuery('DROP TABLE IF EXISTS tempAction'..cc_GUID..';')
end

function cc_splitString(inputstr, seperator)
    if seperator == nil then
        seperator = "%s"
    end
    local t={}
    for str in string.gmatch(inputstr, "([^"..seperator.."]+)") do
        table.insert(t, str)
    end
    return t
end

function cc_normalizeCharacterName(name)
    if name == nil then
        return nil
    end

    local normalised = string.lower(name)
    normalised = normalised:gsub("^%l", string.upper)
    return normalised
end

function cc_has_value (tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return true
        end
    end
    return false
end

function cc_resumeSubRoutine(eventId, delay, repeats)
    if cc_subRoutine == nil then
        RemoveEventById(eventId)
        return
    end
    local ok, err = coroutine.resume(cc_subRoutine)
    if not ok then
        RemoveEventById(eventId)
        cc_subRoutine = nil
        cc_copyFailed("copy", err)
    elseif coroutine.status(cc_subRoutine) == "dead" then
        RemoveEventById(eventId)
        cc_subRoutine = nil
    end
end

local PLAYER_EVENT_ON_COMMAND = 42
local PLAYER_EVENT_ON_LOGOUT = 4

-- The copy runs on a timer, not on the player, so it finishes even if the source player logs out.
-- The lock is only released when it is done (or by cc_copyFailed), so a second copy can't start in between.
local function cc_OnPlayerLogout(event, player)
    if cc_scriptIsBusy ~= 0 and cc_playerGUID ~= nil and tonumber(tostring(player:GetGUID())) == cc_playerGUID then
        PrintInfo("CarbonCopy: source player (GUID "..cc_playerGUID..") logged out mid-copy. The copy continues.")
    end
end

-- function to be called when the command hook fires
-- automatic cleanup of old mailed-items log rows (Config.mailItemLogRetentionDays, 0 = never)
if cc_enableMailItemLog and cc_mailLogRetentionDays > 0 then
    local function cc_autoCleanup()
        local count = cc_cleanupMailLog(cc_mailLogRetentionDays)
        if count > 0 then
            PrintInfo("CarbonCopy: deleted "..count.." mailed-items log row(s) older than "..cc_mailLogRetentionDays.." day(s).")
        end
    end
    cc_autoCleanup()
    CreateLuaEvent(cc_autoCleanup, 86400000, 0)
end

RegisterPlayerEvent(PLAYER_EVENT_ON_COMMAND, cc_CopyCharacter)
RegisterPlayerEvent(PLAYER_EVENT_ON_LOGOUT, cc_OnPlayerLogout)
