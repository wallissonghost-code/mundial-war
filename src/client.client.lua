-- Mundial War 0.6: pooled row renderer, selection, icons and operation labels.
local Players=game:GetService("Players")
local UIS=game:GetService("UserInputService")
local RS=game:GetService("ReplicatedStorage")
local GuiService=game:GetService("GuiService")
local function screenPoint(p) return Vector2.new(p.X,p.Y)-GuiService:GetGuiInset() end
local remote=RS:WaitForChild("MundialWar")
local player=Players.LocalPlayer
local gui=Instance.new("ScreenGui") gui.Name="MundialWarUI" gui.ResetOnSpawn=false gui.DisplayOrder=20
gui.Parent=player:WaitForChild("PlayerGui")
local function make(class,parent,p)
 local o=Instance.new(class) for k,v in pairs(p) do o[k]=v end o.Parent=parent return o
end
local bg=make("Frame",gui,{Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(10,22,33),BorderSizePixel=0})
local title=make("TextLabel",bg,{Size=UDim2.new(1,0,0,27),BackgroundTransparency=1,Text="MUNDIAL WAR · 0.6",TextColor3=Color3.fromRGB(235,210,155),TextSize=17,Font=Enum.Font.GothamBold})
local status=make("TextLabel",bg,{Position=UDim2.fromOffset(6,27),Size=UDim2.new(1,-12,0,35),BackgroundTransparency=1,Text="Carregando mapa…",TextColor3=Color3.new(1,1,1),TextSize=12,TextWrapped=true})
local view=make("ScrollingFrame",bg,{Position=UDim2.fromOffset(6,65),Size=UDim2.new(1,-12,1,-223),BackgroundColor3=Color3.fromRGB(23,65,94),BorderSizePixel=0,ScrollBarThickness=4,CanvasSize=UDim2.fromOffset(0,0),ScrollingDirection=Enum.ScrollingDirection.XY})
local map=make("Frame",view,{BackgroundTransparency=1,Size=UDim2.fromOffset(800,450)})
local selection=make("TextLabel",bg,{Position=UDim2.new(0,8,1,-154),Size=UDim2.new(1,-16,0,30),BackgroundTransparency=1,Text="Toque em terra livre para fundar sua nação.",TextColor3=Color3.fromRGB(235,210,155),TextSize=12,TextWrapped=true})
local toast=make("TextLabel",bg,{Position=UDim2.fromOffset(12,66),Size=UDim2.new(1,-24,0,28),BackgroundColor3=Color3.fromRGB(12,27,39),TextColor3=Color3.new(1,1,1),TextSize=12,TextWrapped=true,Visible=false,ZIndex=8})
local state,cells,regions,water,rows,icons,labels=nil,{},{},{},{},{},{}
local selected=nil
local ratio,zoom,mode=.25,1,nil
local round=0
local needRows={}
local palette={Color3.fromRGB(110,150,210),Color3.fromRGB(204,118,119),Color3.fromRGB(191,156,99),Color3.fromRGB(165,129,192),Color3.fromRGB(107,180,185),Color3.fromRGB(174,188,107)}
local function color(id)
 if id==-1 then return Color3.fromRGB(23,65,94) end
 if id==0 then return Color3.fromRGB(215,215,215) end
 if state and id==state.you then return Color3.fromRGB(91,201,141) end
 return palette[math.abs(id)%#palette+1]
end
local function message(text)
 toast.Text=text toast.Visible=true
 local token=os.clock() toast:SetAttribute("Token",token)
 task.delay(4,function() if toast:GetAttribute("Token")==token then toast.Visible=false end end)
end
local function resize()
 local aspect=state and state.w/state.h or 16/9
 local width=math.max(100,math.min(view.AbsoluteSize.X,view.AbsoluteSize.Y*aspect))*zoom
 map.Size=UDim2.fromOffset(width,width/aspect)
 map.Position=UDim2.fromOffset(math.max(0,(view.AbsoluteSize.X-width)/2),math.max(0,(view.AbsoluteSize.Y-width/aspect)/2))
 view.CanvasSize=UDim2.fromOffset(width,width/aspect)
end
view:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
local buttons={}
local function bar(y,entries)
 local f=make("Frame",bg,{Position=UDim2.new(0,6,1,y),Size=UDim2.new(1,-12,0,36),BackgroundTransparency=1})
 make("UIListLayout",f,{FillDirection=Enum.FillDirection.Horizontal,Padding=UDim.new(0,3),HorizontalAlignment=Enum.HorizontalAlignment.Center})
 for _,e in ipairs(entries) do
  local b=make("TextButton",f,{Size=UDim2.new(1/#entries,-3,1,0),Text=e[1],TextSize=11,TextWrapped=true,Font=Enum.Font.GothamBold,TextColor3=Color3.new(1,1,1),BackgroundColor3=Color3.fromRGB(35,56,72),BorderSizePixel=0})
  b.Activated:Connect(function() e[2](b) end)
  if e[3] then buttons[e[3]]=b end
 end
end
local function send(action)
 if not selected then message("Selecione uma célula no mapa primeiro.") return end
 remote:FireServer(action,selected,ratio)
end
bar(-120,{{"Avançar",function() mode=nil send("attack") end},{"25%",function(b) local values={.1,.25,.5,.75,1} ratio=values[table.find(values,ratio)%5+1] b.Text=math.floor(ratio*100).."%" end},{"Parar",function() remote:FireServer("stop") end},{"−",function() zoom=math.max(1,zoom/1.4) resize() end},{"+",function() zoom=math.min(10,zoom*1.4) resize() end},{"Mapa",function() zoom=1 resize() view.CanvasPosition=Vector2.zero end},{"Reiniciar",function() remote:FireServer("restart") end}})
local entries={}
for _,e in ipairs({{"city","▥ Cidade 500"},{"factory","⚙ Fábrica 700"},{"bunker","◆ Bunker 400"},{"port","⚓ Porto 900"},{"naval","⛵ Invadir"}}) do
 local kind=e[1]
 entries[#entries+1]={e[2],function()
  if not state then return end
  if mode==kind then mode=nil else mode=kind end
  for k,b in pairs(buttons) do b.BackgroundColor3=mode==k and Color3.fromRGB(117,92,41) or Color3.fromRGB(35,56,72) end
  message(mode and (kind=="naval" and "Toque numa costa para enviar a frota." or state.types[kind].description.." · Toque numa célula sua vazia.") or "Modo seleção.")
 end,kind}
end
bar(-80,entries)
bar(-40,{{"⚔ Declarar guerra",function() send("war") end},{"☮ Tratado",function() send("truce") end},{"🤝 Aliança",function() send("ally") end},{"✓ Aceitar",function() send("accept") end}})
local marker=make("Frame",map,{BackgroundTransparency=1,Size=UDim2.fromOffset(14,14),AnchorPoint=Vector2.new(.5,.5),Visible=false,ZIndex=6})
make("UIStroke",marker,{Color=Color3.fromRGB(255,221,88),Thickness=2})
local function selectedInfo()
 if not selected or not state then return end
 local id=cells[selected]
 local n=state.nations[tostring(id)]
 local structure=state.buildings[tostring(selected)]
 local text=n and (n.name.." · "..math.floor(n.troops).." tropas atuais da nação") or "Terra livre"
 if n and id~=state.you then
  local a,b=state.you,id if a>b then a,b=b,a end
  local r=state.relations[tostring(a)..":"..tostring(b)]
  if r and (not r.untilTime or r.untilTime>state.time) then
   text=text.." · "..({war="Em guerra",ally="Aliado",truce="Trégua"})[r.kind]
   if r.untilTime then text=text.." ("..math.ceil(r.untilTime-state.time).."s)" end
  else text=text.." · Neutro" end
 end
 if structure then text=text.." · "..state.types[structure].name.." ("..state.types[structure].description..")" end
 selection.Text=text.." · Avançar para confirmar"
 marker.Visible=true
 marker.Position=UDim2.fromScale(((selected-1)%state.w+.5)/state.w,(math.floor((selected-1)/state.w)+.5)/state.h)
end
local function pick(p)
 if not state then return end
 local rel=p-map.AbsolutePosition
 local x=math.floor(rel.X/map.AbsoluteSize.X*state.w)
 local y=math.floor(rel.Y/map.AbsoluteSize.Y*state.h)
 if x<0 or x>=state.w or y<0 or y>=state.h then return end
 local i=y*state.w+x+1
 if cells[i]==-1 then return end
 selected=i selectedInfo()
 if not state.nations[tostring(state.you)] then remote:FireServer("attack",i,ratio)
 elseif mode=="naval" then remote:FireServer("naval",i,ratio)
 elseif mode then remote:FireServer("build",i,mode) end
end
local function within(p)
 local a,b=view.AbsolutePosition,view.AbsoluteSize
 return p.X>=a.X and p.Y>=a.Y and p.X<a.X+b.X and p.Y<a.Y+b.Y
end
local start,dragInput,scrollStart=nil,nil,nil
UIS.InputBegan:Connect(function(input)
 if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
  local p=screenPoint(input.Position)
  if within(p) then start=p dragInput=input scrollStart=view.CanvasPosition end
 end
end)
UIS.InputEnded:Connect(function(input)
 if start and (input==dragInput or input.UserInputType==Enum.UserInputType.MouseButton1) then
  local p=screenPoint(input.Position)
  if (p-start).Magnitude<7 and (view.CanvasPosition-scrollStart).Magnitude<7 and within(p) then pick(p) end
  start=nil dragInput=nil
 end
end)
UIS.InputChanged:Connect(function(input)
 if start and dragInput and dragInput.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseMovement then
  local delta=screenPoint(input.Position)-start
  view.CanvasPosition=Vector2.new(math.clamp(scrollStart.X-delta.X,0,math.max(0,map.AbsoluteSize.X-view.AbsoluteSize.X)),math.clamp(scrollStart.Y-delta.Y,0,math.max(0,map.AbsoluteSize.Y-view.AbsoluteSize.Y)))
 end
 if input.UserInputType==Enum.UserInputType.MouseWheel and within(screenPoint(UIS:GetMouseLocation())) then
  zoom=math.clamp(zoom*(input.Position.Z>0 and 1.15 or 1/1.15),1,10) resize()
 end
end)
local pinchStart=1
UIS.TouchPinch:Connect(function(points,scale,velocity,inputState)
 if #points<2 or not within(screenPoint(points[1])) then return end
 start=nil
 if inputState==Enum.UserInputState.Begin then pinchStart=zoom end
 zoom=math.clamp(pinchStart*scale,1,10) resize()
end)
local function rowRender(y)
 local w,h=state.w,state.h
 local pool=rows[y] or {} rows[y]=pool local used=0
 local function rect(x,width,top,height,c)
  used=used+1
  local f=pool[used]
  if not f then f=make("Frame",map,{BorderSizePixel=0,Active=false}) pool[used]=f end
  f.Position=UDim2.fromScale(x/w,(y+top)/h) f.Size=UDim2.fromScale(width/w,height/h)
  f.BackgroundColor3=c f.Visible=true
 end
 local x=0
 while x<w do
  local i=y*w+x+1 local id=cells[i] local shade=id==-1 and water[i] or 0 local stop=x+1
  while stop<w and cells[y*w+stop+1]==id and (id~=-1 or water[y*w+stop+1]==shade) do stop=stop+1 end
  rect(x,stop-x,0,1,id==-1 and (shade==1 and Color3.fromRGB(35,97,137) or color(-1)) or color(id))
  x=stop
 end
 local ink=Color3.fromRGB(29,33,37)
 local function differs(i,j) return not cells[j] or cells[i]~=cells[j] or (cells[i]~=-1 and regions[i]~=regions[j]) end
 x=0
 while x<w do
  local i=y*w+x+1
  if cells[i]~=-1 and (y==0 or differs(i,i-w)) then
   local stop=x+1
   while stop<w do local j=y*w+stop+1 if cells[j]==-1 or (y>0 and not differs(j,j-w)) then break end stop=stop+1 end
   rect(x,stop-x,0,.14,ink) x=stop
  else x=x+1 end
 end
 for col=0,w-1 do
  local i=y*w+col+1
  if cells[i]~=-1 then
   if col==0 or differs(i,i-1) then rect(col,.14,0,1,ink) end
   if col==w-1 or cells[i+1]==-1 then rect(col+.86,.14,0,1,ink) end
   if y==h-1 or cells[i+w]==-1 then rect(col,1,.86,.14,ink) end
  end
 end
 for k=used+1,#pool do pool[k].Visible=false end
end
local rendering=false
local function flush()
 if rendering then return end rendering=true
 task.spawn(function()
  while next(needRows) do
   local count=0
   for y in pairs(needRows) do needRows[y]=nil rowRender(y) count=count+1 if count>=8 then break end end
   task.wait()
  end
  rendering=false
 end)
end
local function position(i) return UDim2.fromScale(((i-1)%state.w+.5)/state.w,(math.floor((i-1)/state.w)+.5)/state.h) end
local function buildingIcon(parent,kind)
 local white=Color3.new(1,1,1)
 local function r(x,y,w,h) return make("Frame",parent,{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundColor3=white,BorderSizePixel=0,ZIndex=5}) end
 if kind=="city" then
  r(4,3,11,13) for x=6,12,3 do for y=5,11,3 do local f=r(x,y,1,2) f.BackgroundColor3=Color3.fromRGB(18,33,43) end end
 elseif kind=="factory" then
  r(3,9,13,7) r(12,3,3,8) r(4,7,3,3) r(8,6,3,4)
 elseif kind=="bunker" then
  r(4,7,11,8) r(6,5,7,2) local f=r(7,9,5,2) f.BackgroundColor3=Color3.fromRGB(18,33,43)
 else
  r(9,3,2,13) r(5,7,10,2) r(4,13,12,2) r(3,10,2,4) r(15,10,2,4)
 end
end
local function dynamic()
 for key,obj in pairs(icons) do if not state.buildings[key] then obj:Destroy() icons[key]=nil end end
 for key,kind in pairs(state.buildings) do
  local obj=icons[key]
  if not obj then obj=make("Frame",map,{Size=UDim2.fromOffset(19,19),AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=Color3.fromRGB(18,33,43),BorderSizePixel=0,ZIndex=4}) buildingIcon(obj,kind) icons[key]=obj end
  obj.Position=position(tonumber(key))
 end
 local live={}
 for id,n in pairs(state.nations) do if n.land>0 and n.target~=nil then
  local key="front"..id live[key]=true
  local obj=labels[key]
  if not obj then obj=make("TextLabel",map,{Size=UDim2.fromOffset(142,32),AnchorPoint=Vector2.new(.5,1),BackgroundColor3=Color3.fromRGB(15,30,42),TextColor3=Color3.new(1,1,1),TextSize=11,TextWrapped=true,ZIndex=5}) labels[key]=obj end
  obj.Position=position(n.front)
  obj.Text=n.name.." · "..math.floor(n.troops).." tropas\n"..n.status
 end end
 for id,f in pairs(state.fleets) do
  local key="ship"..id live[key]=true
  local obj=labels[key]
  if not obj then obj=make("TextLabel",map,{Size=UDim2.fromOffset(88,23),AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=Color3.fromRGB(19,42,57),TextColor3=Color3.new(1,1,1),TextSize=12,ZIndex=5}) labels[key]=obj end
  local k=math.clamp(1+math.floor((1-f.remaining/f.duration)*(#f.route-1)),1,#f.route)
  obj.Position=position(f.route[k]) obj.Text="⛵ "..f.troops.." · "..math.ceil(f.remaining).."s"
 end
 for key,obj in pairs(labels) do if not live[key] then obj:Destroy() labels[key]=nil end end
 local n=state.nations[tostring(state.you)]
 status.Text=n and string.format("Tropas %d  ·  Ouro %d  ·  Mundo %.1f%%  ·  %s",math.floor(n.troops),math.floor(n.gold),n.land/state.total*100,n.status) or "Escolha uma célula cinza para começar."
 if state.winner then status.Text="VITÓRIA: "..state.winner.." · 80% conquistados. Use Reiniciar."
 elseif n and n.land<=0 then status.Text="DERROTA · Seu território foi conquistado. Reiniciar quando não houver outros jogadores ativos." end
 if state.offers then selection.Text="Proposta de "..(state.nations[tostring(state.offers.from)] or {name="nação"}).name.." · selecione o território dela e Aceitar."
 else selectedInfo() end
end
remote.OnClientEvent:Connect(function(data)
 if data.notice then message(data.notice) return end
 if data.cells then
  if round~=data.round then
   selected=nil marker.Visible=false selection.Text="Toque em terra livre para fundar sua nação."
   for _,pool in pairs(rows) do for _,f in ipairs(pool) do f:Destroy() end end
   rows={} needRows={} round=data.round
  end
  cells=data.cells regions={} water={}
  for y,line in ipairs(data.regionRows) do for x=1,data.w do regions[(y-1)*data.w+x]=tonumber(string.sub(line,(x-1)*3+1,x*3),16) end end
  for i,v in ipairs(cells) do
   if v==-1 then
    local x=(i-1)%data.w
    water[i]=((x>0 and cells[i-1]~=-1) or (x<data.w-1 and cells[i+1]~=-1) or (i>data.w and cells[i-data.w]~=-1) or (i<=#cells-data.w and cells[i+data.w]~=-1)) and 1 or 0
   end
  end
  for y=0,data.h-1 do needRows[y]=true end
 elseif round~=data.round then remote:FireServer("sync") return end
 state=data
 for _,d in ipairs(data.delta or {}) do
  cells[d[1]]=d[2] local y=math.floor((d[1]-1)/data.w)
  needRows[y]=true if y>0 then needRows[y-1]=true end if y<data.h-1 then needRows[y+1]=true end
 end
 resize() dynamic() flush()
end)
remote:FireServer("sync")
