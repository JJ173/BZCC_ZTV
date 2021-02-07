--[[
	Zjourney.lua: Written by AI_Unit
	Original Concept: TimeVirus (RIP) & Zeeder
	Summary: Main mission script for Zjourney. Converted from 1.2.
]]

assert(load(assert(LoadFile("_requirefix.lua")),"_requirefix.lua"))();

-- Scripts
local _ZTVTauntLogic = require('_ZTVTauntLogic');

-- Objective Text
local _obj1 = "Commander, we need a base, and we need it quickly!";

-- Timers 
local _RockslideTimer = 20 * 60 -- 20 minutes.

local MissionVars = {
	TPS = 0,

	-- Ints
	StratTeam = 1,
	CPUTeamNumber = 6,
	TurnCounter = 0,
	NumHumans = 0, 
	ElapsedGameTime = 0,
	MissionTimer = 0,
	MissionState = 0,
	DropshipDoorSoundTimer = 0,
	RockslideTimer = 0,

	-- Strings
	TempMsgString,

	-- Bools
	GameOver,

	-- Tables
	TeamPos = {},
	TeamIsSetUp = {},
	NotedRecyclerLocation = {},
	SpawnedAtTime = {},

	-- MISSION RELATED VARIABLES
	HumanRecy,
	Dropship,
	MainPlayer,
	Nav1,
	Nav2
}

function Save()
	return MissionVars;
end

function Load(...)
    if select('#', ...) > 0 then
		MissionVars = ...;
    end
end

function InitialSetup()
	MissionVars.TPS = EnableHighTPS();
	AllowRandomTracks(true)

	local preloadODF = {
		"ivrecy",
		"ivtank",
		"ivscout",
		"ivscav",
	}

	for k,v in pairs(preloadODF) do
		PreloadODF(v)
	end
end

function AddObject(h)

end

function DeleteObject(h)

end

function SetupTeam(team)
	local TeamRace = GetRaceOfTeam(team);
	local Where;

	if team < 1 or team >= 16 then
		return;
	end

	if IsTeamplayOn() and MissionVars.TeamIsSetUp[team] then
		return;
	end

	if IsTeamplayOn() then
		SetMPTeamRace(WhichTeamGroup(team), TeamRace);
	end

	Where = GetRandomSpawnpoint(team);
	MissionVars.TeamPos[team] = Where;

	if IsTeamplayOn() then
		for i = GetFirstAlliedTeam(team), GetLastAlliedTeam(team) do
			if i ~= team then
				local newPos = GetPositionNear(Where, 30.0, 60.0);
				MissionVars.TeamPos[i] = newPos;
			end
		end
	end
end

function SetupPlayer(team)
	local PlayerH;
	local Where;
	local TeamBlock = WhichTeamGroup(team);

	if team < 0 or team >= 16 then
		return;
	end

	MissionVars.SpawnedAtTime[team] = MissionVars.ElapsedGameTime;

	if not IsTeamplayOn() or TeamBlock < 0 then
		SetupTeam(team);
		Where = MissionVars.TeamPos[team];
		Where.y = TerrainFindFloor(Where.x, Where.z) + 1.0;
	else
		SetupTeam(GetCommanderTeam(team));
		Where = MissionVars.TeamPos[team];
		Where.y = TerrainFindFloor(Where.x, Where.z) + 1.0;
	end

	PlayerH = BuildObject(GetPlayerODF(Team), Team, spawnpointPosition);

	if (team == 0) then
		MakeInert(PlayerH);
	end

	-- Make sure NumHumans is updated.
	MissionVars.NumHumans = MissionVars.NumHumans + 1;

	return PlayerH;
end

function AddPlayer(id, Team, IsNewPlayer)
	if IsNewPlayer then
		local PlayerH = SetupPlayer(Team)
		SetAsUser(PlayerH, Team)
		AddPilotByHandle(PlayerH)
	end

	return 1
end

function DeletePlayer(id)
	MissionVars.NumHumans = MissionVars.NumHumans - 1;
end

function CountAlliedPlayers(team)
	local count = 0;
	
	for i = 1, 16 do
		if (IsTeamAllied(i, team)) then
			local h = GetPlayerHandle(i);
			if (h ~= nil) then
				count = count + 1;
			end
		end
	end

	return count;
end

function PlayerEjected(DeadObjectHandle)
	local deadObjectTeam = GetTeamNum(DeadObjectHandle);
	if (deadObjectTeam == 0) then
		return 2;
	end

	return 0;
end

function ObjectKilled(DeadObjectHandle, KillersHandle)
	local isDeadAI = not IsPlayer(DeadObjectHandle);
	local isDeadPerson = IsPerson(DeadObjectHandle);

	if (GetCurWorld() ~= 0) then
		return DoEjectPilot;
	end

	local deadObjectTeam = GetTeamNum(DeadObjectHandle);

	if(deadObjectTeam == 0) then
		return 0;
	end

	return DeadObject(DeadObjectHandle, KillersHandle, isDeadPerson, isDeadAI);
end

function ObjectSniped(DeadObjectHandle, KillersHandle)
	local isDeadAI = not IsPlayer(DeadObjectHandle);

	if (GetCurWorld() ~= 0) then
		return 2;
	end

	return DeadObject(DeadObjectHandle, KillersHandle, true, isDeadAI);
end

function RespawnPilot(deadObjectHandle, Team)
	local spawnPointPosition = SetVector(0, 0, 0);

	if (IsAround(MissionVars.HumanRecy)) then
		spawnPointPosition = GetPosition2(MissionVars.HumanRecy);
	end

	local oldPos = GetPosition2(deadObjectHandle);

	local respawnHeight = 200.0;
	if ((math.abs(oldPos.x) > 0.01) and (math.abs(oldPos.z) > 0.01)) then
		local dx = oldPos.x - spawnPointPosition.x;
		local dz = oldPos.z - spawnPointPosition.z;
		local distanceAway = math.sqrt((dx * dx) + (dz * dz));

		if (distanceAway < 100.0) then
			respawnHeight = 35.0;
		else
			local numAllies = CountAlliedPlayers(Team);
			respawnHeight = 30.0 + (math.sqrt(distanceAway) * 1.25);
			local minRespawnHeight = 40.0;
			local maxRespawnHeight = 72.0 + (15.0 * numAllies);

			if (respawnHeight < minRespawnHeight) then
				respawnHeight = minRespawnHeight;
			elseif (respawnHeight > maxRespawnHeight) then
				respawnHeight = maxRespawnHeight;
			end
		end
	end

	spawnPointPosition.x = spawnPointPosition.x + (GetRandomFloat(1.0) - 0.5) * (2.0 * 32.0);
	spawnPointPosition.z = spawnPointPosition.z + (GetRandomFloat(1.0) - 0.5) * (2.0 * 32.0);

	local curFloor = TerrainFindFloor(spawnPointPosition.x, spawnPointPosition.z) + 2.5;
	if (spawnPointPosition.y < curFloor) then
		spawnPointPosition.y = curFloor;
	end

	spawnPointPosition.y = spawnPointPosition.y + respawnHeight;

	local NewPerson = BuildObject("ispilo", Team, spawnPointPosition);
	SetAsUser(NewPerson, Team);
	AddPilotByHandle(NewPerson);
	SetRandomHeadingAngle(NewPerson);

	if (Team == 0) then
		MakeInert(NewPerson);
	end

	return 0;
end

function DeadObject(deadObjectHandle, KillersHandle, isDeadPerson, isDeadAI)
	local deadTeam = GetTeamNum(deadObjectHandle)

	if (deadTeam == 0) then
		return 0
	end

	if (isDeadAI) then
		if (isDeadPerson) then
			return 2 -- DLLHandled
		else
			return 0 -- DoEjectPilot
		end
	else
		if (isDeadPerson) then
			return RespawnPilot(deadObjectHandle, deadTeam)
		else
			return 0 -- DoEjectPilot
		end
	end
end

function HandleGameTime() 
	MissionVars.ElapsedGameTime = MissionVars.ElapsedGameTime + 1;

	if MissionVars.ElapsedGameTime % MissionVars.TPS then
		local Seconds = MissionVars.ElapsedGameTime / MissionVars.TPS;
		local Minutes = Seconds / 60;
		local Hours = Minutes / 60;

		Seconds = Seconds % 60;
		Minutes = Minutes % 60;

		if (Hours ~= 0) then
			MissionVars.TempMsgString = ("Mission Time: %d:%02d:%02d\n"):format(Hours, Minutes, Seconds);
		else
			MissionVars.TempMsgString = ("Mission Time: %d:%02d\n"):format(Minutes, Seconds);
		end

		SetTimerBox(MissionVars.TempMsgString);
	end
end

function Update()
	MissionVars.TurnCounter = MissionVars.TurnCounter + 1;

	HandleGameTime();
	HandleMissionLogic();
end

-----------------------
-- COOP MISSION CODE --
-----------------------
function Start()
	-- MP Stuff
	SetAutoGroupUnits(false);
	WantBotKillMessages();

	-- Counting Players
	MissionVars.NumHumans = CountPlayers();

	-- IMPORTANT SERVER STUFF --
	local PlayerH;
	local PlayerEntryH;
	local LocalTeamNum = GetLocalPlayerTeamNumber();

--	PlayerEntryH = GetPlayerHandle();
--	if IsAround(PlayerEntryH) then
--		RemoveObject(PlayerEntryH);
--	end

--	if ImServer() or not IsNetworkOn() then
--		PlayerH = SetupPlayer(LocalTeamNum);
--		SetAsUser(PlayerH, LocalTeamNum);
--		AddPilotByHandle(PlayerH);
--	end

	-- END IMPORTANT SERVER STUFF --

	-- Start grabbing handles.
	MissionVars.Dropship = GetHandle("PlayerDropship");
	MissionVars.HumanRecy = GetHandle("HumanRecy");

	SetAnimation(MissionVars.Dropship, "deploy", 1);

	-- Make sure the dropship emitters are masked.
	MaskEmitter(MissionVars.Dropship, 0);
end

function HandleMissionLogic() 
	MissionVars.MainPlayer = GetPlayerHandle(1);

	if (MissionVars.MissionTimer < MissionVars.TurnCounter) then
		if (MissionVars.MissionState == 0) then
			-- Set the first objective and create the nav that we need.
			MissionVars.Nav1 = BuildObject("ibnav", MissionVars.StratTeam, "goto1");
			
			-- Name the nav to "base".
			SetObjectiveName(MissionVars.Nav1, "Base");

			-- Set the objective and the markers.
			SetObjectiveOn(MissionVars.Nav1);

			-- Set the first objective.
			AddObjective(_obj1, "WHITE", 10);

			-- Wait before the dropship takes off.
			MissionVars.DropshipDoorSoundTimer = MissionVars.DropshipDoorSoundTimer + SecondsToTurns(2);

			-- Advance the mission state.
			MissionVars.MissionState = MissionVars.MissionState + 1;
		elseif (MissionVars.MissionState == 1) then
			if (MissionVars.DropshipDoorSoundTimer < MissionVars.TurnCounter) then
				-- Play the sound of the doors opening.
				StartSoundEffect("dropdoor.wav");

				MissionVars.MissionState = MissionVars.MissionState + 1;
			end
		elseif (MissionVars.MissionState == 2) then
			if (GetDistance(MissionVars.HumanRecy, MissionVars.Dropship) > 75) then
				-- Make sure the dropship takes off.
				SetAnimation(MissionVars.Dropship, "takeoff", 1);
				StartEmitter(MissionVars.Dropship, 1);
				StartEmitter(MissionVars.Dropship, 2);
				StartSoundEffect("dropleav.wav");

				-- Advance the mission state.
				MissionVars.MissionState = MissionVars.MissionState + 1;
			end
		elseif (MissionVars.MissionState == 3) then
			if (IsDeployed(MissionVars.HumanRecy)) then
				-- Start the main portion of the mission.
				ClearObjectives();
				AddObjective(_obj1, "GREEN", 10);

				-- Remove marker from Nav1
				SetObjectiveOff(MissionVars.Nav1);

				-- Set AIP?

				-- Set timer for Rocksliders.
				MissionVars.RockslideTimer = MissionVars.RockslideTimer + SecondsToTurns(_RockslideTimer);

				-- Advance the mission state.
				MissionVars.MissionState = MissionVars.MissionState + 1;
			end
		elseif (MissionVars.MissionState == 4) then
			if (MissionVars.RockslideTimer < MissionVars.TurnCounter) then
				-- Spawn the rockslide turrets.
				for i = 1, 8 do 
					BuildObject("fvrckart", MissionVars.CPUTeamNumber, "bang"..i);
				end

				-- Set objective to move to next location.
				MissionVars.Nav2 = BuildObject("ibnav", MissionVars.StratTeam, "goto2");
			
				-- Name the nav to "base".
				SetObjectiveName(MissionVars.Nav1, "Relocate Base");

				-- Set the objective and the markers.
				SetObjectiveOn(MissionVars.Nav2);

				-- Advance the mission state.
				MissionVars.MissionState = MissionVars.MissionState + 1;
			end
		end
	end
end