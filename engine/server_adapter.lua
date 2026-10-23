local round=1
local known={}
local function playerId(p) return 1000000000000+p.UserId end
local function snapshot(p,full)
 local public,structures,ships={}, {}, {}
 for id,n in pairs(nations) do public[tostring(id)]=n end
 for i,t in pairs(buildings) do structures[tostring(i)]=t end
 for id,f in pairs(fleets) do ships[tostring(id)]=f end
 local delta={} for i,id in pairs(changed) do delta[#delta+1]={i,id} end
 local function send(player)
  local initial=full or known[player.UserId]~=round
  local data={round=round,you=playerId(player),w=W,h=H,nations=public,buildings=structures,fleets=ships,types=types,total=total,winner=winner,time=clock,relations=relations,offers=offers[tostring(playerId(player))] or offers[playerId(player)],delta=delta}
  if initial then data.cells=cells data.regionRows=regionRows known[player.UserId]=round end
  remote:FireClient(player,data)
 end
 if p then send(p) else for _,player in ipairs(Players:GetPlayers()) do send(player) end changed={} end
end
remote.OnServerEvent:Connect(function(p,action,i,value)
 local now=os.clock()
 if now-(cooldown[p.UserId] or -10)<.1 then return end
 cooldown[p.UserId]=now
 local id=playerId(p)
 if action=="sync" then snapshot(p,true) return end
 if action=="restart" then
  local alive=0
  for other,n in pairs(nations) do if other>0 and n.land>0 then alive=alive+1 end end
  if winner or alive==0 then resetRound() round=round+1 snapshot(nil,true)
  else remote:FireClient(p,{notice="Uma partida ainda está ativa. Reinício disponível no fim."}) end
  return
 end
 if winner then return end
 local n=nations[id]
 if action=="stop" then if n then n.target=nil n.status="Parado" end snapshot(nil) return end
 if type(i)~="number" or i~=i or i%1~=0 or i<1 or i>#cells then return end
 local ok,message=false,"Ação inválida."
 if action=="attack" then
  if not n then
   ok=spawn(id,p.DisplayName,i)
   if ok and not started then seedBots() started=true end
   message=ok and "Nação fundada." or "Escolha uma terra livre."
  else ok,message=order(id,i,value) end
 elseif action=="build" then
  ok=type(value)=="string" and build(id,i,value)
  message=ok and "Construção concluída." or "Precisa de terra sua vazia e ouro suficiente. Porto exige litoral."
 elseif action=="naval" then ok,message=embark(id,i,value)
 elseif action=="war" or action=="truce" or action=="ally" or action=="accept" then ok,message=diplomacy(id,cells[i],action) end
 remote:FireClient(p,{notice=message})
 snapshot(nil)
end)
Players.PlayerRemoving:Connect(function(p)
 local id=playerId(p)
 if owned[id] then local list={} for i in pairs(owned[id]) do list[#list+1]=i end
  for _,i in ipairs(list) do claim(0,i) buildings[i]=nil end
 end
 nations[id]=nil owned[id]=nil edges[id]=nil fleets[id]=nil cooldown[p.UserId]=nil known[p.UserId]=nil
 snapshot(nil)
end)
while task.wait(.25) do tick(.25) snapshot(nil) end
