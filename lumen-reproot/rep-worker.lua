  -- Lumen's Rep-root worker, extended with live switches and a custom mount.
  -- Approach, collision snapshot, cancellation and recovery are
  -- supplied by the original flingOne transaction around this worker.
  local function repWork(part, burst)
    if not K.repAvailable() then refusal = "this executor has no sethiddenproperty" return end
    local studio = L.RepRoot
    if not studio or not studio.repRoot then refusal = "Rep Root is off" return end
    local t0 = tick()
    local targetCharacter=target.Character
    if not repBind(root, part) then refusal = "rep-root write refused" return end
    local flip = 1
    local wasFling = studio.fling
    local launchedAt, burn = nil, newBurn()
    studio.workerActive = true
    studio.workerAt = os.clock()
    repeat
      if not (root and root.Parent and part.Parent) then break end
      if not studio.repRoot or not attemptActive() then break end
      if studio.fling ~= wasFling then
        t0=tick(); launchedAt=nil; burn=newBurn(); wasFling=studio.fling
      end
      if target.Character~=targetCharacter or LP.Character~=ch or not target.Parent then break end
      if thum and thum.Health<=0 then break end
      local position=part.Position
      if not studio.validPosition(position) then refusal="invalid target position" break end
      observeTargetSpeed(part)
      -- Preserve Lumen's write-through compatibility. Some executors read nil
      -- after a successful write, so nil is not evidence of a dead property.
      if repRead(root) ~= part then
        if not repBind(root, part) then refusal = "rep-root rebind refused" break end
      end
      local elapsed = tick() - t0
      local desired = studio.mount(part, part.Position, elapsed)
      studio.observe(part, root, desired)
      root.CFrame = desired
      if studio.fling then
        forceCollide()
        local thrust, angular = studio.drive(repAimVector(), part, elapsed, flip)
        root.AssemblyLinearVelocity = thrust
        root.AssemblyAngularVelocity = angular
      else
        -- The same Rep Root binding, with all high-velocity driving disabled.
        for _, d in ipairs(ch:GetDescendants()) do
          if d:IsA("BasePart") then
            if collideWas[d] == nil then collideWas[d] = d.CanCollide end
            d.CanCollide = false
          end
        end
        local v = part.AssemblyLinearVelocity
        root.AssemblyLinearVelocity = v.Magnitude < 200 and v or Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
      end
      flip = -flip
      if studio.fling and not launchedAt and part.AssemblyLinearVelocity.Magnitude > K.cfg.flungAt then
        launchedAt = tick(); burn.at, burn.lastT = launchedAt, launchedAt
        burn.last = part.AssemblyLinearVelocity.Magnitude
      end
      RS.Heartbeat:Wait()
      if not attemptActive() then break end
      local limit = studio.fling and (burst and math.min(0.30, K.cfg.flingDuration) or K.cfg.flingDuration) or studio.holdLimit
      if studio.queue then
        limit=studio.queue.single and math.huge or studio.turnDuration
        if burst and studio.fling then limit=math.min(limit,0.30) end
      end
      if tick() > t0 + limit then break end
    until (not studio.queue and studio.fling and launchedAt and burnDone(burn, part.AssemblyLinearVelocity.Magnitude, tick()))
        or not K.flinging or not L.live() or (thum and thum.Sit) or hum.Health <= 0
    studio.workerActive = false
    repBind(root, root)
  end

  local function repBurstWork(part)
    repWork(part, true)
  end
