local Config = {}
local cc_maps = {}
local ticket_Cost = {}

-- Name of Eluna dB scheme
Config.customDbName = 'ac_eluna'

-- Table names inside Config.customDbName
Config.carboncopyTableName = 'carboncopy'
Config.playerLogsTableName = 'carboncopy_player_logs'
Config.adminLogsTableName = 'carboncopy_admin_logs'
Config.mailItemsTableName = 'carboncopy_mail_items'

-- Enable or disable writing of logs and auto creation of log tables
Config.enablePlayerLogs = true
Config.enableAdminLogs = true

-- Log every item mailed by a copy (with enchants, gems and random suffix) so an admin can restore it
-- with .carboncopy restore $characterName [missing|all]. Also auto-creates the table above.
Config.enableMailItemLog = true

-- Delete mailed-items log entries automatically once they are this many days old (checked at startup and once a day).
-- 0 = never delete. GMs can also do it by hand with .carboncopy cleanup $days.
Config.mailItemLogRetentionDays = 0

-- Min GM Level to use the .carboncopy command. Set to 0 for all players.
Config.minGMRankForCopy = 0

-- Min GM Level to add tickets to an account.
Config.minGMRankForTickets = 2

-- Min GM Level to list and restore mailed items (.carboncopy restore).
Config.minGMRankForRestore = 2

-- Days the copy / restore mails stay in the mailbox. 0 = never expire (until 2038). -1 = core default (30 days).
-- Expired GM mail is deleted together with its items, it is never returned.
Config.mailExpireDays = 0

-- Seconds to wait, after a copy is fully done and the new character unlocked, before telling the player they can log out.
Config.doneMessageDelay = 5

-- While a character is locked for a copy / restore, how often (milliseconds) to check whether a kicked character is
-- offline and whether the mails are saved, and how many times to check before giving up (250 x 60 = 15 seconds).
-- Lower interval = shorter lock. Minimum 50 ms.
Config.pollIntervalMs = 250
Config.pollMaxAttempts = 60

-- The amount of free tickets to grant when .carboncopy is executed for the first time on that account
Config.freeTickets = 4

-- Signature at the end of the copy / restore mails. The mail texts themselves (all languages) are in CarbonCopy_Locale.lua.
Config.mailSignature = "the team of ChromieCraft!"

-- Empty equipment slots (and totems the shaman doesn't have) send nothing.
-- Set an item entry here to get the old behaviour back and pad the mails with it, e.g. 38 = Recruit's Shirt.
Config.emptySlotFiller = 0

-- Maximum level to allow copying a character.
Config.maxLevel = 79

-- Whether the ticket amount withdrawn for a copy is always 1 (set it to "single") or depends on the level (set this to "level")
Config.ticketCost = "level"

-- Keep starting / existing items on the target character instead of deleting all except hearthstone (true = yes | false = no)
Config.keepStartingItems = false

-- Whether to copy equipment sets to the new character (requires "Use Equipment Manager" enabled in Interface > Features) (true = yes | false = no)
Config.copyEquipmentSets = false

-- Copied (and restored) items: true = add the soulbound flag to the original item's flags.
-- false = keep exactly the original item's flags (a soulbound original gives a soulbound copy, an unbound BoE stays unbound).
Config.makeCopySoulbounded = true

-- Here you can adjust the cost in tickets if Config.ticketCost is set to "level"
ticket_Cost[19] = 1
ticket_Cost[29] = 1
ticket_Cost[39] = 1
ticket_Cost[49] = 1      -- it costs 1 ticket to copy a character up to level 49
ticket_Cost[59] = 2
ticket_Cost[69] = 2      -- it costs 2 tickets to copy a character up to level 69
ticket_Cost[79] = 3      -- it costs 3 tickets to copy a character up to level 79
ticket_Cost[80] = 25     -- it costs 25 tickets to copy a character at level 80

-- The maps below specify legal locations to use the .carboncopy command.
-- This is used to prevent dungeon specific gear to be copied e.g. the legendaries from the Kael'thas encounter.

-- Eastern kingdoms
cc_maps[1] = 0

-- Kalimdor
cc_maps[2] = 1

-- Outland
cc_maps[3] = 530

-- Northrend
cc_maps[4] = 571

return {
    Config = Config,
    cc_maps = cc_maps,
    ticket_Cost = ticket_Cost,
}
