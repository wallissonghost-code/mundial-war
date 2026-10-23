"""Build a local Studio place without downloading a Roblox template."""
from pathlib import Path
import xml.etree.ElementTree as E
root_dir=Path(__file__).resolve().parents[1]
root=E.Element("roblox",version="4")
E.SubElement(root,"External").text="null"
E.SubElement(root,"External").text="nil"
def item(parent,kind,name):
    obj=E.SubElement(parent,"Item",{"class":kind,"referent":"RBX"+name})
    props=E.SubElement(obj,"Properties")
    E.SubElement(props,"string",name="Name").text=name
    return obj,props
workspace,p=item(root,"Workspace","Workspace")
E.SubElement(p,"bool",name="StreamingEnabled").text="false"
players,p=item(root,"Players","Players")
E.SubElement(p,"bool",name="CharacterAutoLoads").text="false"
item(root,"ReplicatedStorage","ReplicatedStorage")
server,p=item(root,"ServerScriptService","ServerScriptService")
script,p=item(server,"Script","MundialWarServer")
E.SubElement(p,"ProtectedString",name="Source").text=(root_dir/"src/server.server.lua").read_text()
starter,p=item(root,"StarterPlayer","StarterPlayer")
scripts,p=item(starter,"StarterPlayerScripts","StarterPlayerScripts")
client,p=item(scripts,"LocalScript","MundialWarClient")
E.SubElement(p,"ProtectedString",name="Source").text=(root_dir/"src/client.client.lua").read_text()
out=root_dir/"dist/Mundial_War_Alpha_0_3.rbxlx"
out.parent.mkdir(parents=True,exist_ok=True)
E.ElementTree(root).write(out,encoding="utf-8",xml_declaration=True)
parsed=E.parse(out)
for node,file in zip(parsed.findall(".//ProtectedString"),["server.server.lua","client.client.lua"]):
    assert node.text==(root_dir/"src"/file).read_text()
assert parsed.find(".//Item[@class='StarterPlayerScripts']/Item[@class='LocalScript']") is not None
print(out)
