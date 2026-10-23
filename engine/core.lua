-- Portable rules shared with the embedded server build; no Roblox APIs.
local cells,nations,buildings,fleets,coastal,adj,edges,owned,changed={},{},{},{},{},{},{},{},{}
local relations,offers={},{}
local clock,started,winner=0,false,nil
local total=0
local types={
 city={cost=500,troops=30,cap=2000,gold=0,mark="▥",name="Cidade",description="+30 tropas/s · +2.000 capacidade"},
 factory={cost=700,troops=0,cap=0,gold=35,mark="⚙",name="Fábrica",description="+35 ouro/s"},
 bunker={cost=400,troops=0,cap=0,gold=0,mark="◆",name="Bunker",description="Dobra a defesa desta célula"},
 port={cost=900,troops=0,cap=0,gold=5,mark="⚓",name="Porto",description="+5 ouro/s · permite frotas"},
}
for y=1,H do for x=1,W do
 local i=(y-1)*W+x
 cells[i]=string.sub(landRows[y],x,x)=="1" and 0 or -1
 if cells[i]==0 then total=total+1 end
 local a={}
 if x>1 then a[#a+1]=i-1 end
 if x<W then a[#a+1]=i+1 end
 if y>1 then a[#a+1]=i-W end
 if y<H then a[#a+1]=i+W end
 adj[i]=a
end end
local function neighbors(i) return adj[i] or {} end
for i,v in ipairs(cells) do if v==0 then for _,j in ipairs(adj[i]) do if cells[j]==-1 then coastal[i]=true break end end end end
local function refresh(i)
 local id=cells[i]
 if id==0 or id==-1 or not edges[id] then return end
 edges[id][i]=nil
 for _,j in ipairs(adj[i]) do if cells[j]~=-1 and cells[j]~=id then edges[id][i]=true break end end
end
local function claim(id,i)
 local old=cells[i]
 if old==id or old==-1 then return end
 if nations[old] then nations[old].land=nations[old].land-1 owned[old][i]=nil edges[old][i]=nil end
 cells[i]=id
 if nations[id] then nations[id].land=nations[id].land+1 owned[id][i]=true end
 changed[i]=id
 refresh(i)
 for _,j in ipairs(adj[i]) do refresh(j) end
end
local function spawn(id,name,i)
 if cells[i]~=0 or nations[id] then return false end
 nations[id]={name=name,troops=id>0 and 2500 or 1500,gold=0,land=0,ratio=.25,anchor=i,front=i,status="Aguardando",spent=0}
 owned[id]={} edges[id]={}
 claim(id,i)
 return true
end
local function pair(a,b) if a>b then a,b=b,a end return tostring(a)..":"..tostring(b) end
local function relation(a,b)
 local r=relations[pair(a,b)]
 if not r then return "neutral" end
 if r.untilTime and r.untilTime<=clock then relations[pair(a,b)]=nil return "neutral" end
 return r.kind
end
local function stopPair(a,b,kind)
 relations[pair(a,b)]={kind=kind,untilTime=clock+(kind=="ally" and 180 or 90)}
 for _,id in ipairs({a,b}) do local n=nations[id]
  if n and n.target==(id==a and b or a) then n.target=nil n.status="Tratado ativo" end
 end
end
local function diplomacy(a,b,kind)
 local n,m=nations[a],nations[b]
 if not n or not m or a==b or n.land<=0 or m.land<=0 then return false,"Nação inválida." end
 if kind=="war" then
  if relation(a,b)=="truce" then return false,"A trégua ainda está ativa." end
  relations[pair(a,b)]={kind="war"}
  return true,"Guerra declarada. Selecione Avançar para avançar."
 end
 if kind=="accept" then
  local o=offers[a]
  if not o or o.from~=b or o.expires<=clock then return false,"Não existe proposta válida desta nação." end
  stopPair(a,b,o.kind) offers[a]=nil
  return true,"Proposta aceita. As conquistas atuais foram mantidas."
 end
 if kind~="ally" and kind~="truce" then return false,"Ação inválida." end
 if b<0 then
  local accepted=kind=="truce" and (n.troops>=m.troops*.65 or m.land<n.land) or kind=="ally" and relation(a,b)~="war" and n.troops>=m.troops*.35
  if not accepted then return false,"A outra nação recusou a proposta." end
  stopPair(a,b,kind)
  return true,"Proposta aceita pela nação. Fronteiras mantidas."
 end
 offers[b]={from=a,kind=kind,expires=clock+30}
 return true,"Proposta enviada; aguarde a aceitação."
end
local function frontier(id,target)
 local out,seen={},{}
 for i in pairs(edges[id] or {}) do for _,j in ipairs(adj[i]) do
  if cells[j]==target and not seen[j] then seen[j]=true out[#out+1]=j end
 end end
 return out
end
local function distance(i,j)
 return ((i-1)%W-(j-1)%W)^2+(math.floor((i-1)/W)-math.floor((j-1)/W))^2
end
local function order(id,i,ratio)
 local n=nations[id]
 if not n or n.land<=0 or cells[i]==-1 or cells[i]==id then return false,"Selecione outra terra." end
 if type(ratio)~="number" or ratio~=ratio or ratio<.1 or ratio>1 then return false,"Percentual inválido." end
 local target=cells[i]
 if target~=0 and relation(id,target)~="war" then return false,"Declare guerra antes de atacar. Alianças e tréguas impedem ataques." end
 local f=frontier(id,target)
 if #f==0 then return false,"Sem fronteira terrestre. Construa um porto para cruzar o mar." end
 n.target=target n.anchor=i n.ratio=ratio n.status=target==0 and "Expandindo" or "Atacando"
 return true,"Avanço iniciado na direção selecionada."
end
local function build(id,i,kind)
 local n,t=nations[id],types[kind]
 if not n or n.land<=0 or not t or cells[i]~=id or buildings[i] then return false end
 if kind=="port" and not coastal[i] then return false end
 if n.gold<t.cost then return false end
 n.gold=n.gold-t.cost buildings[i]=kind
 return true
end
local function bonuses(id)
 local troops,cap,gold=0,0,0
 for i,t in pairs(buildings) do if cells[i]==id then
  troops=troops+types[t].troops cap=cap+types[t].cap gold=gold+types[t].gold
 end end
 return troops,cap,gold
end
local function defense(i)
 local d=nations[cells[i]]
 local cost=d and math.max(25,math.ceil(d.troops/math.max(1,d.land))) or 5
 if buildings[i]=="bunker" then cost=cost*2 end
 return cost
end
local function step(id,n,dt)
 dt=dt or .25
 if n.land<=0 then n.target=nil n.status="Eliminado" return end
 local t,c,g=bonuses(id)
 n.troops=math.min(n.troops+(85+n.land*2+t)*dt,5000+n.land*250+c)
 n.gold=n.gold+(5+n.land+g)*dt n.spent=0
 if n.target==nil then return end
 if n.target~=0 and relation(id,n.target)~="war" then n.target=nil n.status="Ataque encerrado por tratado" return end
 local candidates=frontier(id,n.target)
 if #candidates==0 then n.target=nil n.status="Sem terra acessível; use um porto" return end
 table.sort(candidates,function(a,b)return distance(a,n.anchor)<distance(b,n.anchor)end)
 local budget=math.floor(n.troops*n.ratio)
 local limit=math.min(12,4+math.floor(math.sqrt(n.land)/2))
 local taken=0
 local seen={} for _,i in ipairs(candidates) do seen[i]=true end
 while #candidates>0 and taken<limit do
  local i=table.remove(candidates,1)
  if cells[i]==n.target then
   local cost=defense(i)
   if n.spent+cost<=budget then
    local d=nations[cells[i]]
    if d then d.troops=math.max(0,d.troops-cost) end
    n.spent=n.spent+cost n.front=i claim(id,i) taken=taken+1
    for _,j in ipairs(adj[i]) do if cells[j]==n.target and not seen[j] then seen[j]=true candidates[#candidates+1]=j end end
    table.sort(candidates,function(a,b)return distance(a,n.anchor)<distance(b,n.anchor)end)
   end
  end
 end
 n.troops=math.max(0,n.troops-n.spent)
 n.status=taken>0 and (n.target==0 and "Expandindo" or "Atacando") or "Aguardando tropas; aumente o percentual"
end
local function seaRoute(id,target)
 if not coastal[target] or cells[target]==id then return nil end
 local queue,previous={},{}
 for i,t in pairs(buildings) do if t=="port" and cells[i]==id then for _,j in ipairs(adj[i]) do
  if cells[j]==-1 and previous[j]==nil then previous[j]=0 queue[#queue+1]=j end
 end end end
 local finish={} for _,j in ipairs(adj[target]) do if cells[j]==-1 then finish[j]=true end end
 local head=1
 while head<=#queue do
  local i=queue[head] head=head+1
  if finish[i] then
   local reverse={target}
   while i~=0 do reverse[#reverse+1]=i i=previous[i] end
   local result={} for k=#reverse,1,-1 do result[#result+1]=reverse[k] end
   return result
  end
  for _,j in ipairs(adj[i]) do if cells[j]==-1 and previous[j]==nil then previous[j]=i queue[#queue+1]=j end end
 end
 return nil
end
local function embark(id,i,ratio)
 local n=nations[id]
 if not n or n.land<=0 or fleets[id] then return false,"Sem território ou frota já em viagem." end
 if type(ratio)~="number" or ratio~=ratio or ratio<.1 or ratio>1 then return false,"Percentual inválido." end
 if cells[i]~=0 and cells[i]~=-1 and relation(id,cells[i])~="war" then return false,"Declare guerra ao destino primeiro." end
 local troops=math.floor(n.troops*ratio)
 if n.gold<250 or troops<100 then return false,"Precisa de 250 ouro e 100 tropas selecionadas." end
 local path=seaRoute(id,i)
 if not path then return false,"Destino sem rota de água a partir de um porto seu." end
 n.gold=n.gold-250 n.troops=n.troops-troops
 local duration=math.max(3,math.ceil(#path/6))
 fleets[id]={target=i,troops=troops,route=path,duration=duration,remaining=duration}
 return true,"Frota enviada."
end
local function advanceFleets(dt)
 for id,f in pairs(fleets) do
  local n=nations[id]
  if not n or n.land<=0 then fleets[id]=nil
  else
   f.remaining=f.remaining-(dt or .25)
   if f.remaining<=0 then
    local owner=cells[f.target]
    if owner==id or (owner~=0 and relation(id,owner)~="war") then n.troops=n.troops+f.troops
    else
     local cost=defense(f.target)
     local d=nations[owner]
     if f.troops>=cost+50 then
      if d then d.troops=math.max(0,d.troops-cost) end
      claim(id,f.target) n.front=f.target n.troops=n.troops+f.troops-cost-50
     elseif d then d.troops=math.max(0,d.troops-math.floor(f.troops/2)) end
    end
    fleets[id]=nil
   end
  end
 end
end
local seeds={{"Aurora",.18,.20},{"Andes",.28,.60},{"Atlas",.52,.50},{"Boreal",.58,.20},{"Oriente",.77,.30},{"Austral",.82,.73}}
local function seedBots()
 for k,s in ipairs(seeds) do
  local target=math.floor(s[3]*H)*W+math.floor(s[2]*W)+1
  local best,dist=nil,math.huge
  for i,v in ipairs(cells) do if v==0 then local d=distance(i,target)
   if d<dist then best=i dist=d end
  end end
  if best then spawn(-k-1,s[1],best) end
 end
end
local function think(id,n)
 if n.land<=0 then return end
 local free=frontier(id,0)
 if #free>0 then order(id,free[math.random(#free)],.25)
 else
  local targets={}
  for other,m in pairs(nations) do if other~=id and m.land>0 and #frontier(id,other)>0 then targets[#targets+1]=other end end
  table.sort(targets,function(a,b)return nations[a].troops<nations[b].troops end)
  local other=targets[1]
  if other then
   if relation(id,other)=="war" and n.troops<nations[other].troops*.45 then diplomacy(id,other,"truce")
   elseif relation(id,other)~="ally" and relation(id,other)~="truce" and n.troops>nations[other].troops*.8 then
    diplomacy(id,other,"war") local f=frontier(id,other) order(id,f[1],.4)
   end
  end
 end
 if n.gold>=400 then
  local coastCell,edgeCell,inside,hasPort=nil,nil,nil,false
  for i in pairs(owned[id]) do
   if buildings[i]=="port" then hasPort=true end
   if not buildings[i] then
    inside=inside or i
    if coastal[i] then coastCell=coastCell or i end
    if edges[id][i] then edgeCell=edgeCell or i end
   end
  end
  if coastCell and not hasPort and n.gold>=900 then build(id,coastCell,"port")
  elseif edgeCell and n.target and n.target~=0 then build(id,edgeCell,"bunker")
  elseif inside then build(id,inside,n.gold>=700 and "factory" or "city") end
  if hasPort and #free==0 and not fleets[id] and n.troops>1200 then
   local shores={}
   for i in pairs(coastal) do if cells[i]==0 or (cells[i]~=id and relation(id,cells[i])=="war") then shores[#shores+1]=i end end
   if #shores>0 then embark(id,shores[math.random(#shores)],.5) end
  end
 end
end
local aiTimer=0
local function tick(dt)
 if not started or winner then return end
 clock=clock+dt aiTimer=aiTimer+dt
 for id,o in pairs(offers) do if o.expires<=clock or not nations[o.from] or nations[o.from].land<=0 then offers[id]=nil end end
 advanceFleets(dt)
 for id,n in pairs(nations) do
  if id<0 and aiTimer>=2 then think(id,n) end
  step(id,n,dt)
  if n.land/total>=.8 then winner=n.name end
 end
 if aiTimer>=2 then aiTimer=0 end
end
local function resetRound()
 for i,v in ipairs(cells) do if v~=-1 then cells[i]=0 end end
 nations={} buildings={} fleets={} edges={} owned={} changed={} relations={} offers={}
 clock=0 started=false winner=nil aiTimer=0
end
