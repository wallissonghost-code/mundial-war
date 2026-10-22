-- Mundial War 0.1: authoritative territory simulation.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local remote = Instance.new("RemoteEvent")
remote.Name = "MundialWar"
remote.Parent = RS
local W,H = 100,50
-- Original, simplified continent silhouettes; not political boundaries.
local polygons = {
 {{8,10},{18,5},{29,7},{33,13},{25,19},{23,25},{18,23},{15,17},{9,15}},
 {{25,25},{33,27},{36,32},{32,41},{28,45},{26,36},{23,29}},
 {{37,4},{43,3},{44,9},{40,13},{37,9}},
 {{44,16},{52,14},{59,19},{58,28},{53,36},{49,33},{46,25},{42,21}},
 {{44,13},{46,8},{51,7},{52,11},{59,8},{68,6},{83,7},{92,12},{86,17},{79,18},{75,25},{69,23},{65,19},{59,19},{54,14}},
 {{77,34},{87,32},{92,37},{88,42},{79,41}},
 {{91,43},{94,40},{95,43},{92,46}},
 {{60,32},{62,30},{62,35},{60,37}},
 {{80,27},{88,28},{89,30},{81,30}},
}
local function inside(x,y,p)
 local hit=false
 local j=#p
 for i=1,#p do
  local a,b=p[i],p[j]
  if (a[2]>y) ~= (b[2]>y) and x<(b[1]-a[1])*(y-a[2])/(b[2]-a[2])+a[1] then hit=not hit end
  j=i
 end
 return hit
end
local cells, nations, cooldown = {},{},{}
local total=0
for y=1,H do for x=1,W do
 local land=false
 for _,p in ipairs(polygons) do if inside(x,y,p) then land=true break end end
 cells[(y-1)*W+x]=land and 0 or -1
 if land then total=total+1 end
end end
local function neighbors(i)
 local a={}
 local x=(i-1)%W+1
 if x>1 then table.insert(a,i-1) end
 if x<W then table.insert(a,i+1) end
 if i>W then table.insert(a,i-W) end
 if i<=W*(H-1) then table.insert(a,i+W) end
 return a
end
local function spawn(id,name,i)
 if cells[i]~=0 or nations[id] then return false end
 nations[id]={name=name,troops=id>0 and 2500 or 1500,gold=0,land=1,target=nil,ratio=.25}
 cells[i]=id
 return true
end
local function frontier(id,target)
 local a={}
 for i,owner in ipairs(cells) do
  if owner==target then
   for _,j in ipairs(neighbors(i)) do
    if cells[j]==id then table.insert(a,i) break end
   end
  end
 end
 return a
end
local function step(id,n)
 if n.land<=0 then n.target=nil return end
 n.troops=math.min(n.troops+85+n.land*2,5000+n.land*250)
 n.gold=n.gold+5+n.land
 if n.target==nil then return end
 local border=frontier(id,n.target)
 if #border==0 then n.target=nil return end
 local budget=math.floor(n.troops*n.ratio)
 local used=0
 for k=1,math.min(8,#border) do
  local index=math.random(#border)
  local i=table.remove(border,index)
  local defender=nations[cells[i]]
  local cost=defender and math.max(35,math.ceil(defender.troops/math.max(1,defender.land))) or 20
  if used+cost>budget then break end
  used=used+cost
  if defender then
   defender.troops=math.max(0,defender.troops-cost)
   defender.land=defender.land-1
  end
  cells[i]=id
  n.land=n.land+1
 end
 n.troops=math.max(0,n.troops-used)
end
local seeds={{"Aurora",18,12},{"Andes",29,32},{"Atlas",50,22},{"Boreal",60,12},{"Oriente",78,13},{"Austral",84,37}}
for k,s in ipairs(seeds) do spawn(-k-1,s[1],(s[3]-1)*W+s[2]) end
local winner=nil
local function snapshot(p)
 local data={w=W,h=H,cells=cells,nations=nations,total=total,winner=winner}
 if p then remote:FireClient(p,data) else remote:FireAllClients(data) end
end
remote.OnServerEvent:Connect(function(p,action,i,ratio)
 local now=os.clock()
 if now-(cooldown[p.UserId] or -10)<.15 then return end
 cooldown[p.UserId]=now
 if action=="sync" then snapshot(p) return end
 if winner then return end
 if action=="stop" then
  if nations[p.UserId] then nations[p.UserId].target=nil end
  return
 end
 if type(i)~="number" or i~=i or i%1~=0 or i<1 or i>#cells then return end
 local n=nations[p.UserId]
 if not n then spawn(p.UserId,p.DisplayName,i)
 elseif action=="attack" and cells[i]~=-1 and cells[i]~=p.UserId then
  if type(ratio)~="number" or ratio~=ratio then return end
  if #frontier(p.UserId,cells[i])>0 then n.target=cells[i] n.ratio=math.clamp(ratio,.1,1) end
 end
 snapshot(p)
end)
Players.PlayerRemoving:Connect(function(p)
 nations[p.UserId]=nil
 cooldown[p.UserId]=nil
 for i,id in ipairs(cells) do if id==p.UserId then cells[i]=0 end end
end)
while task.wait(1) do
 if not winner then
  for id,n in pairs(nations) do
   if id<0 and n.land>0 then
    if #frontier(id,0)>0 then n.target=0
    elseif math.random()<.3 then
     local targets={}
     for other,m in pairs(nations) do
      if other~=id and m.land>0 and #frontier(id,other)>0 then table.insert(targets,other) end
     end
     n.target=#targets>0 and targets[math.random(#targets)] or nil
    end
   end
   step(id,n)
   if n.land/total>=.8 then winner=n.name break end
  end
 end
 snapshot()
end
