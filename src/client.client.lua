-- Entire map is GUI-based: no 3D streaming distance dependency.
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local player=Players.LocalPlayer
local remote=RS:WaitForChild("MundialWar")
local gui=Instance.new("ScreenGui")
gui.Name="MundialWarUI"
gui.ResetOnSpawn=false
gui.DisplayOrder=20
gui.Parent=player:WaitForChild("PlayerGui")
local function make(class,parent,props)
 local obj=Instance.new(class)
 for k,v in pairs(props) do obj[k]=v end
 obj.Parent=parent
 return obj
end
local bg=make("Frame",gui,{Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.fromRGB(10,20,34),BorderSizePixel=0})
local title=make("TextLabel",bg,{Size=UDim2.new(1,0,0,36),BackgroundTransparency=1,Text="MUNDIAL WAR • ALPHA 0.5",TextColor3=Color3.fromRGB(230,196,112),TextSize=19,Font=Enum.Font.GothamBold})
local status=make("TextLabel",bg,{Position=UDim2.fromOffset(8,36),Size=UDim2.new(1,-16,0,46),BackgroundTransparency=1,Text="Conectando…",TextColor3=Color3.new(1,1,1),TextSize=14,TextWrapped=true,Font=Enum.Font.Gotham})
local view=make("ScrollingFrame",bg,{Position=UDim2.new(0,8,0,86),Size=UDim2.new(1,-16,1,-200),BackgroundColor3=Color3.fromRGB(23,65,94),BorderSizePixel=0,ScrollBarThickness=5,CanvasSize=UDim2.fromOffset(0,0),ScrollingDirection=Enum.ScrollingDirection.XY})
local map=make("Frame",view,{BackgroundTransparency=1,Size=UDim2.fromOffset(800,400)})
local zoom,ratio,state=1,.25,nil
local buttons={}
local lastOwners={}
local lastBuildings={}
local neutralColors={}
local mode=nil
local buildButtons={}
local function resize()
 local aspect=state and state.w/state.h or (16/9)
 local width=math.max(100,math.min(view.AbsoluteSize.X,view.AbsoluteSize.Y*aspect))*zoom
 map.Size=UDim2.fromOffset(width,width/aspect)
 map.Position=UDim2.fromOffset(math.max(0,(view.AbsoluteSize.X-width)/2),math.max(0,(view.AbsoluteSize.Y-width/aspect)/2))
 view.CanvasSize=UDim2.fromOffset(width,width/aspect)
end
view:GetPropertyChangedSignal("AbsoluteSize"):Connect(resize)
local bar=make("Frame",bg,{Position=UDim2.new(0,8,1,-54),Size=UDim2.new(1,-16,0,46),BackgroundTransparency=1})
make("UIListLayout",bar,{FillDirection=Enum.FillDirection.Horizontal,Padding=UDim.new(0,5),HorizontalAlignment=Enum.HorizontalAlignment.Center})
local function control(text,callback)
 local b=make("TextButton",bar,{Size=UDim2.new(.18,0,1,0),Text=text,TextColor3=Color3.new(1,1,1),BackgroundColor3=Color3.fromRGB(36,58,78),TextSize=14,Font=Enum.Font.GothamBold})
 b.Activated:Connect(function() callback(b) end)
 return b
end
control("25%",function(b)
 local values={.1,.25,.5,.75,1}
 local nextIndex=table.find(values,ratio)%#values+1
 ratio=values[nextIndex]
 b.Text=tostring(math.floor(ratio*100)).."%"
end)
control("Parar",function() remote:FireServer("stop") end)
control("−",function() zoom=math.max(1,zoom-.5) resize() end)
control("+",function() zoom=math.min(10,zoom+.5) resize() end)
control("Mapa",function() zoom=1 resize() view.CanvasPosition=Vector2.zero end)
local function landColor(i,data)
 return Color3.fromRGB(215,215,215)
end
-- Decorative game regions, not official national borders.
local regions=nil
local function prepareRegions(data)
 local seeds={}
 for by=0,data.h-1,11 do
  for bx=0,data.w-1,12 do
   local tx=bx+6+((bx*17+by*31)%5-2)
   local ty=by+5+((bx*7+by*13)%5-2)
   local best,dist=nil,math.huge
   for y=by,math.min(by+10,data.h-1) do
    for x=bx,math.min(bx+11,data.w-1) do
     local i=y*data.w+x+1
     if data.cells[i]~=-1 then
      local d=(x-tx)^2+(y-ty)^2
      if d<dist then best={x,y} dist=d end
     end
    end
   end
   if best then table.insert(seeds,best) end
  end
 end
 regions={}
 for i,owner in ipairs(data.cells) do
  if owner~=-1 then
   local x=(i-1)%data.w
   local y=math.floor((i-1)/data.w)
   local best,dist=0,math.huge
   for k,p in ipairs(seeds) do
    local d=(x-p[1])^2+(y-p[2])^2
    if d<dist then best=k dist=d end
   end
   regions[i]=best
   if i%1000==0 then task.wait() end
  end
 end
 -- Blue shallows plus sparse ocean texture; ocean never becomes conquerable.
 for i,owner in ipairs(data.cells) do
  if owner==-1 then
   local x=(i-1)%data.w
   local y=math.floor((i-1)/data.w)
   local distance=4
   for dy=-2,2 do for dx=-2,2 do
    local xx,yy=x+dx,y+dy
    if xx>=0 and xx<data.w and yy>=0 and yy<data.h and data.cells[yy*data.w+xx+1]~=-1 then
     distance=math.min(distance,math.max(math.abs(dx),math.abs(dy)))
    end
   end end
   if distance<=2 or (x*17+y*29)%47==0 then
    local c=distance==1 and Color3.fromRGB(35,97,137) or distance==2 and Color3.fromRGB(29,81,115) or Color3.fromRGB(26,73,103)
    make("Frame",map,{Position=UDim2.fromScale(x/data.w,y/data.h),Size=UDim2.fromScale(1/data.w,1/data.h),BorderSizePixel=0,BackgroundColor3=c,Active=false})
   end
  end
 end
end
local function decorateCell(b,i,data)
 local x=(i-1)%data.w
 local y=math.floor((i-1)/data.w)
 local edges={
  {x==0 or regions[i-1]~=regions[i],0,0,.15,1},
  {x==data.w-1 or regions[i+1]~=regions[i],.85,0,.15,1},
  {y==0 or regions[i-data.w]~=regions[i],0,0,1,.15},
  {y==data.h-1 or regions[i+data.w]~=regions[i],0,.85,1,.15},
 }
 for _,e in ipairs(edges) do
  if e[1] then make("Frame",b,{Position=UDim2.fromScale(e[2],e[3]),Size=UDim2.fromScale(e[4],e[5]),BackgroundColor3=Color3.fromRGB(32,35,38),BorderSizePixel=0,Active=false}) end
 end
end
local function color(owner)
 if owner==0 then return Color3.fromRGB(215,215,215) end
 if owner==player.UserId then return Color3.fromRGB(74,200,141) end
 return Color3.fromHSV((math.abs(owner)*.173)%1,.55,.85)
end
local buildbar=make("Frame",bg,{Position=UDim2.new(0,8,1,-106),Size=UDim2.new(1,-16,0,46),BackgroundTransparency=1})
make("UIListLayout",buildbar,{FillDirection=Enum.FillDirection.Horizontal,Padding=UDim.new(0,4),HorizontalAlignment=Enum.HorizontalAlignment.Center})
for _,entry in ipairs({{"city","Cidade 500"},{"factory","Fábrica 700"},{"bunker","Bunker 400"},{"port","Porto 900"},{"naval","Invadir mar"}}) do
 local kind=entry[1]
 local b=make("TextButton",buildbar,{Size=UDim2.new(.19,0,1,0),Text=entry[2],TextColor3=Color3.new(1,1,1),BackgroundColor3=Color3.fromRGB(36,58,78),TextSize=11,TextWrapped=true,Font=Enum.Font.GothamBold})
 buildButtons[kind]=b
 b.Activated:Connect(function()
  mode=mode==kind and nil or kind
  for key,button in pairs(buildButtons) do button.BackgroundColor3=key==mode and Color3.fromRGB(146,107,35) or Color3.fromRGB(36,58,78) end
 end)
end
local info=make("TextLabel",bg,{Position=UDim2.fromOffset(16,88),Size=UDim2.new(1,-16,0,30),BackgroundColor3=Color3.fromRGB(10,20,34),BackgroundTransparency=.15,Text="",TextColor3=Color3.new(1,1,1),TextSize=12,TextWrapped=true,Visible=false,ZIndex=4})
local noticeUntil=0
local shipMarkers={}
local function renderSnapshot(data)
 if data.notice then
  info.Text=data.notice info.Visible=true noticeUntil=os.clock()+3
  return
 end
 if os.clock()>noticeUntil then info.Visible=false end
 state=data
 if not regions then prepareRegions(data) end
 for i,owner in ipairs(data.cells) do
  if owner~=-1 then
   local b=buttons[i]
   if not b then
    local index=i
    b=make("TextButton",map,{Position=UDim2.fromScale(((i-1)%data.w)/data.w,math.floor((i-1)/data.w)/data.h),Size=UDim2.fromScale(1/data.w,1/data.h),BorderSizePixel=0,Text="",AutoButtonColor=false})
    b.Activated:Connect(function()
     local owner=state.cells[index]
     local nation=state.nations[tostring(owner)]
     info.Text=nation and string.format("%s • %d tropas • %d células",nation.name,nation.troops,nation.land) or "Território livre"
     info.Visible=true noticeUntil=os.clock()+3
     if mode=="naval" then remote:FireServer("naval",index,ratio)
     elseif mode then remote:FireServer("build",index,mode)
     else remote:FireServer("attack",index,ratio) end
    end)
    decorateCell(b,i,data)
    buttons[i]=b
    if i%300==0 then task.wait() end
   end
   if lastOwners[i]~=owner then
    b.BackgroundColor3=owner==0 and landColor(i,data) or color(owner)
    lastOwners[i]=owner
   end
   local kind=data.buildings and data.buildings[tostring(i)]
   if lastBuildings[i]~=(kind or false) then
    b.Text=kind and data.types[kind].mark or ""
    b.TextColor3=Color3.fromRGB(10,20,34)
    b.TextScaled=true
    lastBuildings[i]=kind or false
   end
  end
 end
 for id,marker in pairs(shipMarkers) do
  if not (data.fleets and data.fleets[id]) then marker:Destroy() shipMarkers[id]=nil end
 end
 for id,f in pairs(data.fleets or {}) do
  local marker=shipMarkers[id]
  if not marker then
   marker=make("TextLabel",map,{Size=UDim2.fromOffset(18,18),AnchorPoint=Vector2.new(.5,.5),BackgroundColor3=color(tonumber(id)),Text="▲",TextColor3=Color3.new(1,1,1),TextSize=14,ZIndex=3})
   shipMarkers[id]=marker
  end
  local progress=1-f.remaining/f.duration
  local cell=f.route[math.min(#f.route,1+math.floor(progress*(#f.route-1)))]
  marker.Position=UDim2.fromScale(((cell-1)%data.w+.5)/data.w,(math.floor((cell-1)/data.w)+.5)/data.h)
 end
 local n=data.nations[player.UserId] or data.nations[tostring(player.UserId)]
 if data.winner then status.Text="VITÓRIA: "..data.winner.." • 80% do mundo conquistado"
 elseif n and n.land<=0 then status.Text="Seu território foi conquistado. Entre em um novo servidor para jogar novamente."
 elseif n then
  status.Text=string.format("%s  |  Tropas: %d  |  Ouro: %d  |  Mundo: %.1f%%\nSelecione construção e toque em uma célula sua. Toque novamente no botão para voltar ao ataque.",n.name,n.troops,n.gold,n.land/data.total*100)
 else status.Text="Escolha uma célula sem dono para fundar sua nação. Seu território terá verde vivo.\nDepois, toque em terras vizinhas para expandir. Use + e − para zoom."
 end
 local fleet=data.fleets and data.fleets[tostring(player.UserId)]
 if fleet and not data.winner then status.Text=status.Text.." | Frota: "..fleet.remaining.."s ("..fleet.troops.." tropas)" end
 resize()
end
-- Coalesce snapshots while the large map is being initialized across frames.
local rendering=false
local pending=nil
remote.OnClientEvent:Connect(function(data)
 if data.notice then
  info.Text=data.notice info.Visible=true noticeUntil=os.clock()+3
  return
 end
 pending=data
 if rendering then return end
 rendering=true
 while pending do
  local latest=pending pending=nil
  renderSnapshot(latest)
 end
 rendering=false
end)
remote:FireServer("sync")


