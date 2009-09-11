AddCSLuaFile( "cl_init.lua" ) -- Make sure clientside
AddCSLuaFile( "shared.lua" ) -- and shared scripts are sent.

include('shared.lua')

local subdividable_minsize = CreateConVar("subdividable_minsize", 3)

local models = {
	"models/hunter/blocks/cube025x025x025.mdl",
	"models/hunter/blocks/cube05x05x05.mdl",
	"models/hunter/blocks/cube1x1x1.mdl",
	"models/hunter/blocks/cube2x2x2.mdl",
	"models/hunter/blocks/cube4x4x4.mdl",
	"models/hunter/blocks/cube8x8x8.mdl",
}

local subdiv_registry = {}
local last_subdiv_id = 0

local function delete_subdiv(undodata, subdiv_id)
	if not subdiv_registry[subdiv_id] then return end
	for ent,_ in pairs(subdiv_registry[subdiv_id]) do
		ent:Remove()
	end
end

local function MakeSubdividable(ply, Data, size, subdiv_id)
	--if !ply:CheckLimit("wire_hoverdrives") then return nil end
	Data.Model = models[size]
	if not subdiv_id then
		last_subdiv_id = last_subdiv_id + 1
		subdiv_id = last_subdiv_id
	end

	local ent = ents.Create("subdividable")
	if not ent:IsValid() then return end
	duplicator.DoGeneric(ent, Data)
	ent:SetPlayer(ply)
	ent:Spawn()
	ent:Activate()

	duplicator.DoGenericPhysics(ent, ply, Data)

	--ply:AddCount("wire_hoverdrives", ent)
	ply:AddCleanup("props", ent)
	ent.size = size
	
	ent.subdiv_id = subdiv_id
	if not subdiv_registry[subdiv_id] then
		subdiv_registry[subdiv_id] = {}
		print("undo create")
		undo.Create("Subdividable")
			undo.SetPlayer( ply )
			undo.AddFunction(delete_subdiv, subdiv_id)
		undo.Finish()
	end
	subdiv_registry[subdiv_id][ent] = true
	
	return ent
end

function ENT:OnRemove()
	subdiv_registry[self.subdiv_id][self.Entity] = nil
	if not next(subdiv_registry[self.subdiv_id]) then -- no more entries for this id? remove id from table
		subdiv_registry[self.subdiv_id] = nil
	end
end

duplicator.RegisterEntityClass("subdividable", MakeSubdividable, "Data", "size")

function ENT:SpawnFunction( ply, trace )
	if (not trace.Hit) then return end
	
	local ang = ply:EyeAngles()
	ang.y = ang.y + 180
	ang.r = 0
	ang.p = 0
	local ent = MakeSubdividable(ply, { Angle = ang }, 6)
	
	local min = ent:OBBMins()
	ent:SetPos(trace.HitPos - trace.HitNormal * (min.z-32))
	return ent
end

function ENT:Initialize()
	self.Entity:PhysicsInit( SOLID_VPHYSICS )
	self.Entity:SetMoveType( MOVETYPE_VPHYSICS )
	self.Entity:SetSolid( SOLID_VPHYSICS )
	self.Entity:SetUseType(SIMPLE_USE)
	
	local phys = self.Entity:GetPhysicsObject()
	if phys:IsValid() then
		phys:Wake()
	end
	
end

--[[
local subdivs = {
	Vector(-1, -1, -1),
	Vector(-1, -1,  1),
	Vector(-1,  1, -1),
	Vector(-1,  1,  1),
	Vector( 1, -1, -1),
	Vector( 1, -1,  1),
	Vector( 1,  1, -1),
	Vector( 1,  1,  1),
}
]]
local subdivs = {
	{ 1, 1, 1 },
	{ 1, 1, 2 },
	{ 1, 2, 1 },
	{ 1, 2, 2 },
	{ 2, 1, 1 },
	{ 2, 1, 2 },
	{ 2, 2, 1 },
	{ 2, 2, 2 },
}

function ENT:OnTakeDamage(dmginfo)
	if dmginfo:IsExplosionDamage() then
		--self:Remove()
		-- TODO: carve holes
		return
	end
	
	local dmgpos = dmginfo:GetDamagePosition()
	debugoverlay.Cross(dmgpos, 20, 3)
	
	local prop = self.Entity
	while prop.size > subdividable_minsize:GetInt() do
		prop = prop:subdiv(dmgpos)
	end
	prop:Remove()
end

function ENT:Use(ply, caller)
	self:subdiv()
end

	
function ENT:subdiv(proppos)
	local obbcenter = self:OBBCenter()

	proppos = self:WorldToLocal(proppos or Vector())
	local propoffset = {}
	for i = 1,3 do
		propoffset[i] = proppos[i] > obbcenter[i] and 2 or 1
	end

	local newsize = self.size-1
	if newsize < subdividable_minsize:GetInt() then
		--error("Tried to subdiv a cube of size 1")
		self:GetPlayer():ChatPrint("Cubes of this size cannot be divided any further.")
		return
	end
	
	local Data = {
		Angle = self:GetAngles(),
		-- TODO: add more properties
	}
	local ply = self:GetPlayer()
	
	local oldminmax = {
		self:OBBMins(),
		self:OBBMaxs(),
	}
	
	local propatpos
	for _,offset in ipairs(subdivs) do
		local prop = MakeSubdividable(ply, Data, newsize, self.subdiv_id)

		local newminmax = {
			prop:OBBMins(),
			prop:OBBMaxs(),
		}

		local currentpos = Vector()
		local flag = true
		for i = 1,3 do
			local coffset = offset[i]
			currentpos[i] = oldminmax[coffset][i] - newminmax[coffset][i]
			if coffset ~= propoffset[i] then flag = false end
		end
		if flag then propatpos = prop end
		prop:SetPos(self:LocalToWorld(currentpos))

		prop:GetPhysicsObject():EnableMotion(false)
		prop:SetMoveType(MOVETYPE_NONE)
		prop:SetUnFreezable( true )
		prop:DrawShadow(false)

		ply:AddCleanup("props", prop)
	end
	
	self:Remove()
	return propatpos
end

-- unused
local function Nearest(ent, pos)
	local mins, maxs = ent:OBBMins(), ent:OBBMaxs()
	pos = ent:WorldToLocal(pos)
	for i = 1,3 do
		if pos[i] > maxs[i] then pos[i] = maxs[i] end
		if pos[i] < mins[i] then pos[i] = mins[i] end
	end
	return ent:LocalToWorld(pos)
end
