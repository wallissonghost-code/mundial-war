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
local title=make("TextLabel",bg,{Size=UDim2.new(1,0,0,36),BackgroundTransparency=1,Text="MUNDIAL WAR • ALPHA 0.3",TextColor3=Color3.fromRGB(230,196,112),TextSize=19,Font=Enum.Font.GothamBold})
local status=make("TextLabel",bg,{Position=UDim2.fromOffset(8,36),Size=UDim2.new(1,-16,0,46),BackgroundTransparency=1,Text="Conectando…",TextColor3=Color3.new(1,1,1),TextSize=14,TextWrapped=true,Font=Enum.Font.Gotham})
local view=make("ScrollingFrame",bg,{Position=UDim2.new(0,8,0,86),Size=UDim2.new(1,-16,1,-200),BackgroundColor3=Color3.fromRGB(20,61,89),BorderSizePixel=0,ScrollBarThickness=5,CanvasSize=UDim2.fromOffset(0,0),ScrollingDirection=Enum.ScrollingDirection.XY})
local map=make("Frame",view,{BackgroundTransparency=1,Size=UDim2.fromOffset(800,400)})
local zoom,ratio,state=1,.25,nil
local buttons={}
local mode=nil
local buildButtons={}
local function resize()
 local width=math.max(100,math.min(view.AbsoluteSize.X,view.AbsoluteSize.Y*2))*zoom
 map.Size=UDim2.fromOffset(width,width/2)
 view.CanvasSize=UDim2.fromOffset(width,width/2)
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
control("+",function() zoom=math.min(5,zoom+.5) resize() end)
control("Mapa",function() zoom=1 resize() view.CanvasPosition=Vector2.zero end)
local function color(owner)
 if owner==0 then return Color3.fromRGB(165,174,145) end
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
remote.OnClientEvent:Connect(function(data)
 if data.notice then
  info.Text=data.notice info.Visible=true noticeUntil=os.clock()+3
  return
 end
 if os.clock()>noticeUntil then info.Visible=false end
 state=data
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
    buttons[i]=b
   end
   b.BackgroundColor3=color(owner)
   local kind=data.buildings and data.buildings[tostring(i)]
   b.Text=kind and data.types[kind].mark or ""
   b.TextColor3=Color3.fromRGB(10,20,34)
   b.TextScaled=true
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
 else status.Text="Escolha uma célula bege para fundar sua nação. Verde será seu território.\nDepois, toque em terras vizinhas para expandir. Use + e − para zoom."
 end
 local fleet=data.fleets and data.fleets[tostring(player.UserId)]
 if fleet and not data.winner then status.Text=status.Text.." | Frota: "..fleet.remaining.."s ("..fleet.troops.." tropas)" end
 resize()
end)
remote:FireServer("sync")
