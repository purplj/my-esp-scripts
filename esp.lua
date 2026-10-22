local RS = game:GetService("ReplicatedStorage")
local Camera = workspace.CurrentCamera
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Codec = require(RS.MovementV2.RemoteSnapshotCodec)
local Transport = require(RS.MovementV2.Transport)

local actors    = {}
local baselines = {}
local drawings  = {}

local CHAR_HEIGHT     = 5.2
local CHAR_HALF_WIDTH = 1.0
local TIMEOUT         = 10.0

Transport.getClientChannels().RemoteSnapshot.OnClientEvent:Connect(function(data)
    local frame, err = Codec.decode(data)
    if not frame then return end

    local now = tick()

    for _, actor in ipairs(frame.Actors) do
        actors[actor.ActorId] = {
            pos      = actor.Position,
            vel      = actor.Velocity,
            lastSeen = now,
            userId   = actor.UserId,
        }
        baselines[actor.ActorId] = actor
    end

    for _, delta in ipairs(frame.Deltas) do
        local base = baselines[delta.ActorId]
        if base then
            local updated = Codec.applyDeltaToCanonicalBaseline(base, delta, true)
            if updated then
                baselines[delta.ActorId] = updated
                actors[delta.ActorId] = {
                    pos      = updated.Position,
                    vel      = updated.Velocity,
                    lastSeen = now,
                    userId   = updated.UserId,
                }
            end
        end
    end

    for _, id in ipairs(frame.RemovedActorIds) do
    end
end)

local function clearDrawings()
    for _, d in ipairs(drawings) do
        pcall(function() d:Remove() end)
    end
    drawings = {}
end

local function w2s(pos)
    local sp, vis = Camera:WorldToViewportPoint(pos)
    return Vector2.new(sp.X, sp.Y), vis, sp.Z
end

local function drawESP(pos, color, frozen, name, dist)
    local hw = CHAR_HALF_WIDTH
    local h  = CHAR_HEIGHT

    local corners = {
        pos + Vector3.new( hw, 0,  hw),
        pos + Vector3.new(-hw, 0,  hw),
        pos + Vector3.new(-hw, 0, -hw),
        pos + Vector3.new( hw, 0, -hw),
        pos + Vector3.new( hw, h,  hw),
        pos + Vector3.new(-hw, h,  hw),
        pos + Vector3.new(-hw, h, -hw),
        pos + Vector3.new( hw, h, -hw),
    }

    local proj = {}
    local anyVis = false
    for i, c in ipairs(corners) do
        local sp, vis, depth = w2s(c)
        proj[i] = {pos=sp, vis=vis, depth=depth}
        if vis and depth > 0 then anyVis = true end
    end
    if not anyVis then return end

    local minX, minY =  math.huge,  math.huge
    local maxX, maxY = -math.huge, -math.huge
    for _, p in ipairs(proj) do
        if p.vis and p.depth > 0 then
            if p.pos.X < minX then minX = p.pos.X end
            if p.pos.Y < minY then minY = p.pos.Y end
            if p.pos.X > maxX then maxX = p.pos.X end
            if p.pos.Y > maxY then maxY = p.pos.Y end
        end
    end
    if minX == math.huge then return end

    local w  = maxX - minX
    local h2 = maxY - minY
    if w < 3 or h2 < 3 or w > 800 or h2 > 800 then return end

    local alpha = frozen and 0.5 or 1
    local corners2D = {
        Vector2.new(minX, minY),
        Vector2.new(maxX, minY),
        Vector2.new(maxX, maxY),
        Vector2.new(minX, maxY),
    }
    for i = 1, 4 do
        local ln = Drawing.new("Line")
        ln.From         = corners2D[i]
        ln.To           = corners2D[i % 4 + 1]
        ln.Color        = color
        ln.Thickness    = frozen and 1 or 2
        ln.Transparency = alpha
        ln.Visible      = true
        table.insert(drawings, ln)
    end

    local vp = Camera.ViewportSize
    local footSP = w2s(pos)
    local tr = Drawing.new("Line")
    tr.From         = Vector2.new(vp.X * 0.5, vp.Y)
    tr.To           = footSP
    tr.Color        = color
    tr.Thickness    = 1
    tr.Transparency = alpha * 0.8
    tr.Visible      = true
    table.insert(drawings, tr)

    local ntxt = Drawing.new("Text")
    ntxt.Text     = name .. (frozen and " ?" or "")
    ntxt.Position = Vector2.new((minX+maxX)/2, minY - 16)
    ntxt.Size     = 13
    ntxt.Color    = color
    ntxt.Outline  = true
    ntxt.Center   = true
    ntxt.Visible  = true
    table.insert(drawings, ntxt)

    local dtxt = Drawing.new("Text")
    dtxt.Text     = dist .. "м"
    dtxt.Position = Vector2.new((minX+maxX)/2, maxY + 3)
    dtxt.Size     = 12
    dtxt.Color    = Color3.new(1,1,1)
    dtxt.Outline  = true
    dtxt.Center   = true
    dtxt.Visible  = true
    table.insert(drawings, dtxt)
end

local LP = Players.LocalPlayer

RunService.Heartbeat:Connect(function(dt)
    clearDrawings()

    local now    = tick()
    local camPos = Camera.CFrame.Position

    for id, data in pairs(actors) do
        local age = now - data.lastSeen

        if age > TIMEOUT then
            actors[id]    = nil
            baselines[id] = nil
            continue
        end

        local predictedPos = data.pos
        if age > 0.1 and data.vel then
            local decay = math.max(0, 1 - age * 0.3)
            predictedPos = data.pos + data.vel * age * decay
        end

        local frozen = age > 0.15
        local footPos = predictedPos - Vector3.new(0, 1.0, 0)
        local dist    = math.floor((camPos - predictedPos).Magnitude)

        local name = tostring(data.userId)
        local pl = Players:GetPlayerByUserId(data.userId)
        if pl then name = pl.Name end

        if pl == LP then continue end

        local color = frozen
            and Color3.fromRGB(255, 165, 0)
            or  Color3.fromRGB(255, 50, 50)

        drawESP(footPos, color, frozen, name, dist)
    end
end)
