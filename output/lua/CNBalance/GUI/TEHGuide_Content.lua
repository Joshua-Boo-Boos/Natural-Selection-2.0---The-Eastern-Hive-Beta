-- CNBalance/GUI/TEHGuide_Content.lua
-- Guide content for N2TEH Beta only. See workspace AGENTS.md.
--
-- Each page is a list of blocks: { style, text, colour }.
--   style:  "h" heading (large, with a rule under it), "s" sub-heading, "p" paragraph, "gap" extra space (text = pixels)
--   colour: optional, a key of kTEHGuideColors (marine, alien, cyan, gold, green, red, purple, text, dim).
--           Defaults: headings cyan, sub-headings gold, paragraphs light grey.
-- Text is centred and wrapped automatically; "\n" forces a line break. Numbers come from CNBalance/Balance.lua,
-- BalanceMisc.lua and BalanceHealth.lua - update them here if those change.

kTEHGuide =
{
    title = "NS2.0-TEH - Help",

    pages =
    {
        -- =========================================================================================================
        {
            button = "Overview",
            blocks =
            {
                { "h", "Welcome to NS2.0-TEH" },
                { "p", "NS2.0-TEH is The Eastern Hive's version of Natural Selection 2.0. You already know how to play NS2; this guide explains only what is different here. Use the buttons above for the details of each role." },
                { "p", "In short: the economy rewards fighting, Marines get many new weapons and four ways to upgrade their Command Station, Aliens get two new lifeforms (the Prowler and the Vokex) and new abilities, and each team has an optional NS1-style mode that changes how the whole team plays." },

                { "h", "The two team modes" },
                { "s", "Military Protocol - Marines" },
                { "p", "Researched by the Marine Commander at the Command Station. Marines stop earning resources from Resource Towers, the Commander gets all of that income instead, and every Alien and Alien structure the team kills pays team resources - the bigger the lifeform, the more it pays. The Commander then supplies the team with weapons and equipment, as in NS1." },
                { "s", "Origin Form - Aliens" },
                { "p", "Researched by the Alien Commander once every Hive is built and upgraded to a Crag, Shade or Shift Hive, and switched on automatically if the Aliens start a round without a Commander. There is no Commander from then on: Gorges build every Alien structure, including Hives, with their own resources, as in NS1." },
                { "s", "Combat Engineers - Marines" },
                { "p", "The Marine counterpart to Origin Form, and the alternative to Military Protocol (the Commander can pick only one). The Marines build the base themselves with their personal resources, and Arms Labs hand out free Weapons and Armor levels." },

                { "h", "Resources" },
                { "p", "Teams start with 60 team resources. Marines start with 15 personal resources, Aliens with 12. Every Resource Tower gives the team 1 team resource and every player 0.125 personal resources each tick; towers beyond the third give half." },
                { "p", "Killing enemy structures gives personal resources to the player who kills them - from 0.1 for small things up to 12-15 for a Command Station or a Hive - so pushing pays. Destroying a Command Station or Hive also gives the killing team 12-20 team resources." },

                { "s", "Bounty" },
                { "p", "Every kill and assist adds to your Bounty, shown under your resources. Killing a player with a high Bounty pays extra, so a player who is dominating becomes a valuable target. Bounty drops by one point every 60 seconds." },

                { "s", "Asking for help" },
                { "p", "Marines who request a medpack or ammo get it themselves instantly for a few personal resources, unless Military Protocol is active. Aliens who request healing get a Nutrient Mist the same way. Details are on the Marines and Aliens pages." },

                { "h", "Respawning" },
                { "p", "Marines respawn in 9 seconds and Aliens in 10. Respawns get slower as the teams tech up (Weapons and Armor 2 and 3, Jetpack and Exosuit labs, biomass 5 and above). Under Military Protocol the Marine slowdown is halved." },

                { "h", "Long rounds" },
                { "p", "With at least 10 human players, a round that reaches 40 minutes starts to wind itself down. Structures on both sides lose health and armour, falling to half over the next 20 minutes. From 55 minutes they keep falling to 15%, while respawn times grow towards double. The timer at the top of your screen counts down to this. Push to end the game before the stalemate does." },

                { "h", "Opening this guide" },
                { "p", "Press the Guide key (0 by default; change it in Options > Mods > NS2.0-TEH), type !guide in chat, or type guide in the console. It works at any time, including while you are dead, spectating or commanding." },
                { "p", "The guide also opens by itself each time you join the server. To stop that, switch off Show Guide Upon Join in Options > Mods > NS2.0-TEH." },
            },
        },

        -- =========================================================================================================
        {
            button = "Marines",
            blocks =
            {
                { "h", "Playing as a Marine", "marine" },
                { "p", "You buy from the Armory and Prototype Lab as usual, but there is much more to choose from, and some of it depends on how your Commander upgrades the Command Station." },

                { "h", "Medpacks and ammo", "marine" },
                { "s", "Without Military Protocol" },
                { "p", "Press your normal medpack or ammo request key and you get it yourself, straight away:\nMedpack: 1 personal resource, 10 second cooldown.\nAmmo: 1.5 personal resources, 40 second cooldown.\nThe two icons next to your resources fill up as the cooldowns finish. If you ask while still on cooldown, the request goes to your Commander instead." },
                { "s", "With Military Protocol" },
                { "p", "Self-service is off. Every request goes to your Commander, who drops medpacks (one Marine, or every hurt Marine in a spot) and ammo for team resources." },

                { "h", "Military Protocol", "marine" },
                { "p", "When your Commander researches Military Protocol, your Resource Tower income stops and the team switches to Military uniforms. You now earn personal resources by killing Aliens:\nSkulk 0.8, Gorge 1.2, Prowler 1.5, Lerk 2, Fade or Vokex 3, Onos 5.\nYou can still buy anything you can afford, but most of your gear should now come from your Commander, who has far more team resources than usual. Dropped weapons stay on the floor 10 seconds longer, so pick up what fallen team-mates leave." },

                { "h", "Combat Engineers", "marine" },
                { "p", "If your Commander chooses Combat Engineers, you build the base, not the Commander." },
                { "s", "Building" },
                { "p", "Every Marine gets a Combat Builder (also on respawn, if weapon slot 4 is free). Placing a structure is free; you pay with your own personal resources while you build it, so building together shares the cost. Prices grow with the size of your team. You can build Extractors, Armories, Observatories, Robotics Factories, Infantry Portals (up to 12), Phase Gates, Sentry Batteries, Prototype Labs, Command Stations and Arms Labs." },
                { "s", "Arms Labs are the upgrades" },
                { "p", "Place each Arms Lab as Armor or Weapons. Every finished lab gives the team the next level of its track for free, up to level 3 each. Destroyed labs take levels away, highest first (Weapons before Armor on a tie), so protect them." },
                { "s", "Structure upgrades and Take Credits" },
                { "p", "With the Combat Builder out, right-click a friendly structure in range to open its upgrade window; upgrades are paid with team resources. Take Credits in the build menu swaps 20 team resources for 20 personal resources (less if you are near the 100 cap)." },

                { "h", "BMAC skins", "marine" },
                { "p", "At the start of a round you choose Biological, BMAC or Random, and your skin is locked for that round. A BMAC (any vanilla NS2 robotic Marine skin) has no health, only armour: your 100 health becomes 50 extra armour, so your total toughness is the same as a biological Marine's." },
                { "p", "A BMAC is repaired by Welders and MACs, and any medpack (self-service or from the Commander) gives it 25 armour instead of health. Life Sustain does not heal it, but Nano Armor works. Like an Exo, a BMAC cannot be set on fire, stunned or knocked back by Stomp, devoured by an Onos or pulled in by a Vokex Vortex; Bile Bomb hurts it and Spores do not." },

                { "h", "New weapons", "marine" },
                { "s", "Revolver" },
                { "p", "6 heavy shots per cylinder, 27.5 damage each." },
                { "s", "Brazier Industries 9 (BI9)" },
                { "p", "A free, fully automatic machine pistol from any Armory: 9 damage a bullet, 33 rounds (32 in the magazine and 1 in the chamber). Like the Revolver it is a permanent secondary - you keep it through death until you buy the Pistol or Revolver instead. The Armory always offers the two secondaries you do not have." },
                { "p", "Idle spin: hold the BI9 still without looking around or using it for 10 seconds to play its gun-spin animation. It plays once every 10 seconds while you remain idle. Moving, looking around, firing, reloading or switching weapons resets the wait." },
                { "s", "SMG" },
                { "p", "Light and fast, with a 42-round magazine." },
                { "s", "Knife" },
                { "p", "30 damage. If an Onos devours you, the Knife does 80 damage from inside it - cut your way out." },
                { "s", "Machine Gun" },
                { "p", "A stronger, more accurate rifle with a 55-round magazine. Available once a Command Station is upgraded to the Weapons Lab." },
                { "s", "Gauss Cannon" },
                { "p", "25 personal resources from a Prototype Lab with the Gauss upgrade. Hard-hitting shots with a small splash, a slow rate of fire and a 6-round magazine. The best answer to fast lifeforms." },
                { "s", "Mines and grenades" },
                { "p", "Mines are sold one at a time for 5 personal resources. Once grenades are researched you can buy Cluster, Pulse and Gas grenades; Gas damages Alien armour and heals Marines standing in the cloud." },

                { "h", "Combat Builder", "marine" },
                { "p", "Once your Commander researches it at the Armory, the Combat Builder costs 3 personal resources and lets you build in the field:\nSupply Depot: refills the health and ammo of Marines around it.\nPortable Sentry: shoots nearby Aliens. You can have 1, 2 with an Advanced Armory, or 3 with a Prototype Lab." },

                { "h", "Exosuits", "marine" },
                { "p", "Bought from the Prototype Lab's buy window once it has the Exosuit upgrade. Pick your arms:\nDual Miniguns, dual Railguns (needs the Gauss upgrade too), dual Flamethrowers,\nor a Claw on the left arm with a Minigun, Railgun or Flamethrower on the right." },
                { "s", "Experimental upgrades" },
                { "p", "After Exosuit experimental research you can add:\nArmour Plating: +100 armour.\nExtra Fuel: thrusters last 30% longer.\nEmergency Ejection: a killing blow ejects you instead; the suit is lost.\nSelf-Destruct: the suit explodes when destroyed, hurting Aliens within 5 metres.\nResupply: team-mates press USE on you for ammo (10 charges, 15 second cooldown)." },

                { "h", "Command Station upgrades", "marine" },
                { "p", "What your Commander's choice gives you:\nWeapons Lab: Machine Gun, Cat Packs, Dragon Breath (bullets set Aliens on fire).\nEquipment Lab: Nano Shield, Life Sustain (health regenerates after combat), Nano Armor (armour regenerates after combat).\nCombustible Lab: instant Commander mines, harder-to-see mines, a faster Grenade Launcher whose impact grenades go off near enemies.\nElectronic Lab: Power Surge, Fusion Extractors that shock attackers, MACs that EMP nearby Aliens." },

                { "h", "The new Aliens", "marine" },
                { "s", "Prowler" },
                { "p", "Fights at range: a shotgun-like Volley, a Rappel that pulls it onto you, Webs that hold you in place, and later Acid Spray. Close the distance and do not stand still in the open." },
                { "s", "Vokex" },
                { "p", "A fast assassin: Shadow Step dashes, double jumps, Acid Rockets, and a Vortex that swallows your grenades and pulls Marines in. Stay with team-mates and cover each other's backs." },
                { "s", "Onos Devour" },
                { "p", "An Onos can swallow a Marine. Inside, you take damage over time; your Knife does 80 damage from in there, and your team can free you by killing the Onos." },
            },
        },

        -- =========================================================================================================
        {
            button = "Marines Commander",
            blocks =
            {
                { "h", "Commanding the Marines", "marine" },
                { "p", "The big differences from vanilla: four Command Station upgrades, Military Protocol, the Exosuit Drop menu and large rewards for destroying the Alien base." },

                { "h", "Command Station upgrades (the chair)", "marine" },
                { "p", "Each Command Station can be upgraded once, for 10 team resources (30 seconds), into one of four labs. Each lab unlocks its own branch, so upgrade different Command Stations into different labs to get more than one." },
                { "s", "Weapons Lab" },
                { "p", "Marines can buy the Machine Gun. You can drop Cat Packs. Research Dragon Breath (30 team resources, needs Weapons 2) to make Marine bullets set Aliens on fire." },
                { "s", "Equipment Lab" },
                { "p", "Nano Shield. Life Sustain: Marines regenerate health after combat. Research Nano Armor (30 team resources, needs Armor 2): more armour, armour regenerates after combat, and stronger Jetpack and Exosuit self-repair." },
                { "s", "Combustible Lab" },
                { "p", "Mine Deploy places a mine instantly where you click (4 team resources; up to 12 of your mines at once, never on infestation). Marine mines become harder for Aliens to see. Research the Grenade Launcher upgrade (25 team resources): faster reloads, and impact grenades go off when enemies are near." },
                { "s", "Electronic Lab" },
                { "p", "Power Surge. Upgrade Extractors into Fusion Extractors (25 team resources each): tougher, and they shock Aliens that attack them. Research MAC EMP Blast (15 team resources): MACs set off an EMP when Aliens come close." },

                { "h", "Military Protocol", "marine" },
                { "p", "Researched at the Command Station: free, 12 seconds. It changes the whole round, so think before you click:\nMarines stop earning Resource Tower income; all of it comes to you (1 team resource per tower per tick).\nMarines earn personal resources only from kills.\nMedpack and ammo requests come to you, and you are expected to drop weapons and Exosuits, as in NS1.\nThe extra respawn time from Marine tech is halved." },
                { "s", "Team resources for every Alien killed" },
                { "p", "Skulk 1, Gorge 2, Prowler 4.35, Lerk 5.7, Fade 11.75, Vokex 14, Onos 26, Drifter 1. Every Prowler and bigger is a real boost to your budget." },
                { "s", "Clearing Hive rooms" },
                { "p", "Alien structures pay a bonus on top of their normal reward: Hive 32, Harvester 3.2, Shell, Spur or Veil 2, Whip, Crag, Shade, Shift or Tunnel 1.6. The bonus is multiplied by your team size: x1 at 12 Marines, rising to x2.5 at 30. A Hive is worth 15 (20 if upgraded) plus the bonus, so wiping out a whole Hive room on a full server pays well over 100 team resources." },

                { "h", "Combat Engineers", "marine" },
                { "p", "The alternative to Military Protocol, also on the Command Station: free, 10 seconds. Starting one greys out the other, and you can still cancel during those 10 seconds." },
                { "p", "Once it finishes you can only select, give orders, Scan, Beacon and run ARCs. The Marines build everything with their personal resources and get free Weapons and Armor levels from Arms Labs. Your team resource income from Resource Towers drops to a third and goes on structure upgrades, ARCs, Scans and Beacons. Recycling a Combat Engineers structure refunds you 20% of the personal resources that went into it, as team resources." },

                { "h", "Exosuit Drop", "marine" },
                { "p", "The Exosuit Drop button opens a menu where you pick the arms and experimental upgrades, then drop the suit for team resources: 40 for the suit, plus its upgrades. Under Military Protocol this is how your team gets its Exosuits." },

                { "h", "Other changes", "marine" },
                { "p", "Multi Medpack (the medpack button): 1 team resource per medpack given, with no limit - a drop that heals 10 Marines costs 10; if the team runs out of resources, the Marines nearest the middle of the ring get theirs first. It works the same whatever is under your cursor (a hurt Marine, a healthy one, or just the floor). It uses the server-registered placement point under your cursor (there is no lock onto a Marine), and every Marine or Jetpack Marine within 4.5 metres who needs a medpack gets one at once (the normal medpack heal, sound and effect on each Marine healed); Marines at full health and Exosuits get nothing. If there is no Marine at all inside the 4.5 metre ring, a normal medpack is left on the ground instead (1 team resource) for anyone to pick up, so you can lay a trail of them; with Marines in the ring but none needing a medpack, it can't be placed (and costs nothing). The medpack stays selected after each drop, so you can keep left-clicking to drop more (Escape, right-click or another button ends it); as Marine Commander, tap and release the middle mouse button to switch between Multi Medpack and Area Heal anytime, even without selecting the medpack. Hold middle mouse for 0.3 seconds to ping once at the cursor instead; releasing after a hold does not switch modes. The big-map order wheel and other players' ping controls are unchanged; the bottom-right of your screen shows the Medpack Mode, and every new Commander starts on Multi Medpack. Area Heal (2 team resources): a blue sentry battery heals every hurt Marine or Jetpack Marine within 4.5 metres by 8 health a second for 5 seconds (no Exos); everyone sees its ring on the ground with blue + signs floating inside it, and a new field replaces an older one it would overlap. Both modes heal in a column across the ring, up to 12 metres above placement height. Area Heal and Multi Medpack both use a cylinder centred horizontally on the server-registered placement point: the ring marks its 4.5 metre horizontal radius, with healing from 3 metres below to 12 metres above that point. The healing origin is not projected onto a lower floor. A clear line of sight is required, so neither heals through solid floors or ceilings. A field can be placed anywhere; while placing one your placement ghost is the sentry battery.\nAmmo packs and Cat Packs cost 1 team resource each, with no cooldown.\nWelders can be dropped for 2 team resources.\nUp to 12 Infantry Portals on the map.\nCombat Builder (Armory research, 10 team resources) lets Marines build Supply Depots and portable Sentries.\nMotion Track (Observatory research, 35 team resources) reveals moving Aliens every 12 seconds.\nThe Prototype Lab is upgraded into a Jetpack, Exosuit or Gauss lab, each unlocking its own items." },
            },
        },

        -- =========================================================================================================
        {
            button = "Aliens",
            blocks =
            {
                { "h", "Playing as an Alien", "alien" },
                { "p", "You evolve with personal resources as usual. What is new: the Prowler and the Vokex, new abilities on the familiar lifeforms, and Origin Form, which turns the Gorges into the team's builders." },
                { "s", "Asking for healing" },
                { "p", "Requesting healing gives you a Nutrient Mist on the spot for 1.5 personal resources (30 second cooldown)." },

                { "h", "Lifeforms and abilities", "alien" },
                { "p", "Prices are in personal resources. The number after an ability is the biomass level it unlocks at." },
                { "s", "Skulk" },
                { "p", "Leap (4). Xenocide (7). Xenocide Fuel (10): a bigger, deadlier Xenocide - 12 metres and 200 damage - that also respawns you faster." },
                { "s", "Gorge - 10" },
                { "p", "Builder menu: Hydras, Clogs, Webs, Chunk (a mine that explodes near Marines) and Babbler Nest (biomass 2, 3 personal resources, hatches Babblers at Marines). Belly Slide goes faster down slopes. Bile Bomb (3)." },
                { "s", "Prowler - 15" },
                { "p", "A ranged lifeform. Volley fires a shotgun-like spread of spikes. Rappel pulls you to your target and damages it. Webs trap Marines in place for a short time. Acid Spray (5) fires acid projectiles." },
                { "s", "Lerk - 21" },
                { "p", "Spores (4). Umbra (6). Primal Scream (8): rallies nearby Aliens with a partial Enzyme that speeds up their attacks." },
                { "s", "Fade - 37" },
                { "p", "Metabolize (2). Advanced Metabolize (5). Stab (7)." },
                { "s", "Vokex - 39" },
                { "p", "An assassin. Shadow Step (1): hold to dash in the direction you are moving; hold jump while stepping to climb. It costs energy to start and while held. Double jump for height. Metabolize (2). Acid Rocket (5): a long-range acid projectile that splashes. Vortex (7): a short-lived vortex that swallows passing projectiles and pulls in and damages nearby enemies." },
                { "s", "Onos - 65" },
                { "p", "Charge. Devour (3): swallow a Marine and digest them. While digesting you take less damage but move slower and cannot use Bone Shield. Bone Shield (5). Stomp (8)." },

                { "h", "Origin Form", "alien" },
                { "p", "With Origin Form there is no Alien Commander. The team only loses when nobody is left alive and nobody can respawn, so losing a Hive is not the end." },
                { "s", "Every Gorge is a builder" },
                { "p", "Gorges get the Worker ability and build every team structure with their own personal resources:\nHive 40 (choose Crag, Shade or Shift), Harvester 8, Whip 8,\nCrag, Shade or Shift 15, Shell, Spur or Veil 12,\nTunnel 6 (exit 2), Egg 2, Cyst 0.5.\nThe team's first Hive builds 5 times faster." },
                { "s", "Biomass comes from support structures" },
                { "p", "Each Hive's biomass comes from its own kind of support structure: a Crag Hive counts Crags, a Shade Hive counts Shades, a Shift Hive counts Shifts.\n1 structure: biomass 2.  3 structures: biomass 3.  6 structures: biomass 4.\nBuilding them is how the team unlocks abilities." },
                { "s", "Biomass Fetch" },
                { "p", "Gorges can buy Biomass Fetch in the evolve menu to move team resources into their own: 60 the first time in a round, 20 after that, only while the team has at least 10. Bots may use it by default; the Bot Biomass Fetch vote (before the round starts) turns it off for bots for the rest of the map." },
                { "s", "Income" },
                { "p", "Harvester income depends on how many Hives the team has: the fewer Hives, the more each Harvester pays. Killing Marines pays personal resources depending on what killed them: Skulk or Gorge 2, Prowler 1.8, Lerk 1.7, Fade, Vokex or Onos 1 - and 1.5 times that for a Jetpacker, twice that for an Exo. Eggs spawn 10% faster." },
            },
        },

        -- =========================================================================================================
        {
            button = "Aliens Commander",
            blocks =
            {
                { "h", "Commanding the Aliens", "alien" },
                { "p", "Much of the Alien Commander's job is as in vanilla. The differences: Origin Form, new lifeform eggs, tunnel upgrades from each Hive type, cheaper biomass recovery, and the Rally Point." },

                { "h", "Origin Form", "alien" },
                { "p", "Once every Hive is built and upgraded into a Crag, Shade or Shift Hive, the Origin Form button on the Hive lights up (free, 12 seconds). When it finishes you are ejected and nobody can command again. Gorges build everything from then on, and Hives get biomass from the Crags, Shades or Shifts around them (see the Aliens page)." },
                { "p", "Only choose it when your Gorges are ready to take over. If the Aliens start a round with no Commander, Origin Form switches on by itself: the team gets 40 extra team resources, the starting Hive is removed, and the Gorges must build the first Hive." },

                { "h", "Biomass", "alien" },
                { "p", "Biomass research costs 30, 40 and 60 team resources. If a Hive loses biomass, Biomass Recover gets it back for less: 10, 15 and 20 team resources." },

                { "h", "Lifeform eggs", "alien" },
                { "p", "Select an Egg to turn it into a lifeform egg:\nGorge (biomass 2), Lerk or Prowler (4), Fade or Vokex (8), Onos (9)." },

                { "h", "Tunnel upgrades", "alien" },
                { "p", "Each Hive type researches its own tunnel upgrade:\nShift Hive - Tunnel Muscle (25): no more travelling through tunnels.\nCrag Hive - Tunnel Shells (15): tougher tunnels, and users get a Mucous shield.\nShade Hive - Tunnel Camouflage (15): entrances are camouflaged out of combat.\nTunnels can also be relocated for 5 team resources." },

                { "h", "Rally Point", "alien" },
                { "p", "Your threat marker is the Rally Point: free, 30 second cooldown, lasts 30 seconds. Each Alien who reaches it (within 4 metres) gets 0.2 personal resources, once per Rally Point. Use it to gather the team for a push." },

                { "h", "Other changes", "alien" },
                { "p", "Up to 6 Commander Whips.\nRupture (biomass 2), Bone Wall (3), Contamination (10), Storm (11).\nKilling a Command Station pays your team 12 team resources, or 15 if it was upgraded." },
            },
        },
    },
}

-- Per-variant history: prepend new dated entries after the heading below.
-- Also update the relevant gameplay page. See the workspace AGENTS.md.
table.insert(kTEHGuide.pages, {
    button = "Changelog",
    blocks = {
        { "h", "NS2.0-TEH - Changelog", "gold" },
        { "s", "2026-10-28 19:56:41 GMT (UTC+00:00)", "gold" },
        { "p", "Marine Commander medpack controls: tap MMB to switch Multi Medpack / Area Heal on release without selecting a medpack; hold MMB for 0.3 seconds to ping once without switching. Previously MMB switched only with medpack selected and otherwise pinged immediately. Big-map order wheel, other players and other ping bindings are unchanged." },
        { "s", "2026-10-28 19:53:42 GMT (UTC+00:00)", "gold" },
        { "p", "Area Heal and Multi Medpack: lower reach 2.7 -> 3 metres; upper reach remains 12 metres and horizontal radius 4.5 metres. Both now measure from the server-registered placement origin instead of projecting it onto a lower floor. Placement eligibility and bot target checks use the same origin. Line-of-sight restrictions remain." },
        { "s", "2026-10-28 19:53:10 GMT (UTC+00:00)", "gold" },
        { "p", "Medpack lower reach: Area Heal 3 -> 2.7 metres; Multi Medpack 0.3 -> 2.7 metres, covering an Exo collision height plus 0.3 metres clearance. Upper reach stays 12 metres, radius 4.5 metres, and line of sight is still required. Self-requested Auto Med heals directly and has no placement-height limit." },
        { "s", "2026-10-28 19:52:20 GMT (UTC+00:00)", "gold" },
        { "p", "Area Heal: lower reach increased from 0.3 to 3 metres below placement height. Upper reach remains 12 metres and radius remains 4.5 metres. Field bot healing-range checks use the same lower reach. Solid floors and ceilings still block healing; Multi Medpack range is unchanged." },
        { "s", "2026-10-28 17:54:16 GMT (UTC+00:00)", "gold" },
        { "p", "Bot Biomass Fetch: now ENABLED by default on every map. The vote turns it off instead - it can only be started before the round starts, and once passed bot Gorges can't use Biomass Fetch for the rest of the map (it is back on after a map change). Was: off by default, a vote turned it on for one round." },
        { "s", "2026-10-28 17:42:39 GMT (UTC+00:00)", "gold" },
        { "p", "Medpack mode switch: the middle mouse button now switches between Multi Medpack and Area Heal only while the medpack is selected - the rest of the time it pings as normal again (it had been blocking the Commander's ping). Tooltips and the Medpack Mode line say so." },
        { "s", "2026-10-28 17:29:48 GMT (UTC+00:00)", "gold" },
        { "p", "Marine Commander: the Medpack and the Ammo Pack stay selected after each drop, so you can keep left-clicking to drop more (Multi Medpacks, Area Heals or Ammo Packs). Escape, right-click or choosing another button or menu ends it." },
        { "s", "2026-10-28 15:37:56 GMT (UTC+00:00)", "gold" },
        { "p", "Medpack button: the tooltip and placement cost now show 2 for Area Heal (1 per medpack for Multi Medpack). The Medpack Mode line has a dark backing so it is easier to read, and moves up above a button's tooltip box while one is showing." },
        { "s", "2026-10-28 15:27:24 GMT (UTC+00:00)", "gold" },
        { "p", "Marine bot Commander: judges who a medpack reaches exactly as the medpack does (floor under the click, the 4.5 metre column up to 12 metres), and no longer tries a Multi Medpack where Marines stand but none needs one." },
        { "s", "2026-10-28 15:26:03 GMT (UTC+00:00)", "gold" },
        { "p", "Multi Medpack: gives a medpack to every Marine or Jetpack Marine in the ring who needs one whatever is under the cursor (it was measuring from the click point, so a click on a Marine's body could miss the Marines on the floor). Short of team resources, the Marines nearest the middle of the ring get theirs first. Area Heal also measures from the floor under the click." },
        { "s", "2026-10-28 15:22:20 GMT (UTC+00:00)", "gold" },
        { "p", "Multi Medpack: a medpack is left on the ground only when there is no Marine at all inside its ring. With Marines in the ring, only those who need one get a medpack and nothing is left on the ground; if none of them needs one it can't be placed (and costs nothing)." },
        { "s", "2026-10-28 15:19:28 GMT (UTC+00:00)", "gold" },
        { "p", "Marine bot Commander: switches between Multi Medpack and Area Heal - an Area Heal for 3 or more hurt Marines together or for hurt Marines near an enemy Hive, otherwise a Multi Medpack - and during Hive rushes places Area Heals on its own over the hurt Marines attacking the Hive. Marine bots walk into Area Heal rings when hurt (and stay fighting when already inside)." },
        { "s", "2026-10-28 15:11:58 GMT (UTC+00:00)", "gold" },
        { "p", "Multi Medpack: when nobody inside its ring needs a medpack it is no longer refused - it is left as one normal medpack on the ground (1 team resource) for anyone to pick up, so the Commander can lay a trail of medpacks." },
        { "s", "2026-10-28 15:08:53 GMT (UTC+00:00)", "gold" },
        { "p", "Medpack: both modes now heal within the same 4.5 metre radius across the floor (Multi Medpack was 5 metres, Area Heal 4 metres)." },
        { "s", "2026-10-28 15:05:45 GMT (UTC+00:00)", "gold" },
        { "p", "Medpack heal area is now a column for both modes: within the ring across the floor, from the height it was placed at up to 12 metres above (Jetpack Marines flying over the ring are healed), never through a floor or ceiling. Was: Multi Medpack within 2.5 metres up or down, Area Heal a 4 metre sphere." },
        { "s", "2026-10-28 15:04:11 GMT (UTC+00:00)", "gold" },
        { "p", "Area Heal can be placed anywhere again (2 team resources). Multi Medpack still only gives medpacks to Marines who need one, and can't be placed (costs nothing) when nobody in its ring does." },
        { "s", "2026-10-28 15:01:28 GMT (UTC+00:00)", "gold" },
        { "p", "Medpack: no more auto-lock onto a Marine - both modes go on the floor under the cursor and heal everyone in their ring who needs it. In Area Heal mode the Commander's placement ghost is the sentry battery instead of the medpack." },
        { "s", "2026-10-28 14:53:34 GMT (UTC+00:00)", "gold" },
        { "p", "Area Heal: translucent blue + signs now float up and down inside the field's ring for everyone, and a field can only be placed where a Marine inside its ring is hurt. Medpack: dropping one locked on a Marine who doesn't need a medpack is refused (nothing placed or charged)." },
        { "s", "2026-10-28 14:43:58 GMT (UTC+00:00)", "gold" },
        { "p", "Medpack modes: the Marine Commander clicks the middle mouse button (big map closed) to switch the medpack between Multi Medpack (default) and Area Heal; the button's icon, name and tooltip and a Medpack Mode line in the bottom-right change with it. Area Heal is back: 2 team resources, 8 health a second for 5 seconds (was 4 a second for 10) within 4 metres, shown to everyone as a solid ring on the ground. Fix: a medpack dropped on a Marine was invisible." },
        { "s", "2026-10-28 03:39:12 GMT (UTC+00:00)", "gold" },
        { "p", "A dropped weapon no longer spills a separate spare-ammo bag: it keeps its own reserve ammo, and whoever picks it up gets it (as in S2TEH and D2TEH). Frees room for maps that add their own objects, such as ns2_craft. The Commander's ammo pack drop is unchanged." },
        { "s", "2026-10-27 21:48:47 GMT (UTC+00:00)", "gold" },
        { "p", "Multi Medpack: a ground drop is refused (no cost) unless a Marine inside the 5 metre ring needs a medpack; the ring no longer shows while the drop is locked on a Marine; the medpack effect plays once on each Marine healed; smaller \"Multi Medpack\" text on the Commander button." },
        { "s", "2026-10-27 21:34:28 GMT (UTC+00:00)", "gold" },
        { "p", "Multi Medpack: ground-drop radius 3 -> 5 metres (every hurt Marine or Jetpack Marine within 5 metres gets a medpack, 1 team resource each; the Commander's ring is now 5 metres)." },
        { "s", "2026-10-27 21:23:02 GMT (UTC+00:00)", "gold" },
        { "p", "Multi Medpack cost: 3 team resources a drop -> 1 per medpack given, with no limit. A drop on a Marine costs 1; a ground drop costs 1 for each Marine within 3 metres who gets a medpack (10 Marines = 10), as long as the team can pay, and nothing if nobody needed one." },
        { "s", "2026-10-27 21:21:26 GMT (UTC+00:00)", "gold" },
        { "p", "Med Field replaced by the Multi Medpack (still 3 team resources): no battery model, energy ring or heal over time. Dropped on a Marine (auto-aim lock) it is a normal medpack for that Marine; dropped on the ground it gives a normal medpack to every Marine or Jetpack Marine within 3 metres who needs one (never Exosuits or Marines at full health). The 3 metre ring shows only when no Marine is under the cursor. New button icon: the medpack with a + and \"Multi Medpack\". Commander bots drop a Multi Medpack in the middle of 2 or more hurt Marines bunched together, otherwise a normal medpack." },
        { "s", "2026-10-27 20:43:10 GMT (UTC+00:00)", "gold" },
        { "p", "Commander bots and the Med Field: they no longer place a field on a Marine who is already inside one, keep at most 3 fields at a time, and never place one over another (which would remove it) - instead the new field goes right next to the old one, towards the Marine, making a short chain. Marine bots that are hurt walk into a nearby field and stay until healed." },
        { "s", "2026-10-27 20:39:07 GMT (UTC+00:00)", "gold" },
        { "p", "Med Field: lasts 10 seconds instead of 8, so it heals up to 40 health instead of 32 (4 a second)." },
        { "s", "2026-10-27 20:17:28 GMT (UTC+00:00)", "gold" },
        { "p", "Commander medpack is now a Med Field: cost 1 -> 3 team resources. Instead of a medpack to pick up, it places a blue sentry-battery model (it powers nothing) with the power node's energy ring for 8 seconds, healing Marines and Jetpack Marines within 4 metres 4 health a second (32 in all; BMACs 2 armour a second; never Exosuits; nothing above full health). A new field that would overlap an older one removes the older one. The Commander button is renamed Med Field, with a new icon (battery, medpack and +), and the Commander sees each field's 4 metre range as a ring on the ground, while placing it and until it ends. Self-service medpacks are unchanged." },
        { "p", "2026-10-26 03:39:11 GMT (UTC+00:00) - BI9 idle spin: added the new view-model animation; plays after 10 idle seconds and repeats every 10 seconds while idle. Actions interrupt the spin and reset the wait." },
        { "s", "2026-10-25 19:23:19 GMT (UTC+00:00)", "gold" },
        { "p", "New weapon: the Brazier Industries 9 (BI9), a free, permanent, fully automatic secondary from any Armory (9 damage, 33 rounds). It replaces the Pistol or Revolver and is kept through death until you buy another secondary. The Armory now shows the two secondaries you do not have: one in the usual secondary slot and one as an extra button below the weapons. Buying any secondary replaces a Motion Tracker, as before." },
        { "s", "2026-10-25 01:47:45 BST (UTC+01:00)", "gold" },
        { "p", "Onos bots: they now use Devour (once researched) to swallow the Marine or Jetpack Marine they are fighting (never a BMAC), and switch back to Gore while digesting. They use the normal Devour weapon and values." },
        { "s", "2026-10-25 00:53:23 BST (UTC+01:00)", "gold" },
        { "p", "Marine bots: buying now comes before following orders and taking territory, so bots with the p-res buy Exos (any unlocked combo, including Claw and Flamethrower Exos, with experimental upgrades), Jetpacks, Gauss Cannons (at the Prototype Lab) and Advanced Armory weapons in the late game." },
        { "s", "2026-10-24 22:28:27 BST (UTC+01:00)", "gold" },
        { "p", "Guide: opens automatically when you join the server. New Show Guide Upon Join switch (on by default) in Options > Mods > NS2.0-TEH." },
        { "s", "2026-10-24 21:46:43 BST (UTC+01:00)", "gold" },
        { "p", "Guide: !guide now shows in the Shine chat auto-complete with help text. Headings restyled. Reputation section removed (not active on these servers). Rally Point text now gives its exact numbers. Added the Beta-only Combat Engineers and BMAC sections." },
        { "s", "2026-10-24 21:45:24 BST (UTC+01:00)", "gold" },
        { "p", "Guide: added this Changelog page. Future gameplay changes are recorded here, and the guide pages are updated with them." },
        { "s", "2026-10-24 (time not recorded)", "gold" },
        { "p", "Vokex Shadow Step: energy cost raised 20%, from 6 to 7.2 to start and from 32 to 38.4 a second while held." },
        { "s", "2026-10-23 (time not recorded)", "gold" },
        { "p", "Bot Biomass Fetch: now a vote in the vote menu, for the current round only. Bot Gorges can never use Biomass Fetch unless the vote has passed, not even for the team's first Hive." },
        { "p", "Older changes are not listed. Only changes whose date is recorded in the code are included.", "dim" },
    },
})
