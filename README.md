# Mundial War — Alpha 0.1

Protótipo original de conquista territorial para Roblox, inspirado no gênero de RoFront/OpenFront. Não utiliza código nem imagens desses jogos.

## Instalação no Roblox Studio
Este repositório começou vazio. Não existe publicação automática GitHub → Roblox configurada.
1. Abra uma experiência nova no Roblox Studio.
2. Crie um Script chamado MundialWar em ServerScriptService e cole src/server.server.lua.
3. Crie um LocalScript chamado MundialWar em StarterPlayer > StarterPlayerScripts e cole src/client.client.lua.
4. Clique em Play. Escolha uma célula bege para começar.
5. Para testar multiplayer, use o teste de servidor com dois jogadores no Studio.

Alternativamente, sincronize usando Rojo com default.project.json. O arquivo descreve apenas os dois scripts; não altera o Workspace.

## Jogabilidade
- Seis bots, continentes simplificados e água não conquistável.
- Jogador começa com 2.500 tropas; bots com 1.500.
- Toque em terra neutra adjacente para iniciar expansão contínua.
- Toque em território de um inimigo com fronteira compartilhada para atacar.
- Percentual selecionado limita o gasto de tropas por segundo; não é um envio único.
- Parar cancela a operação; + / − ajustam zoom; arrastar navega pelo mapa.
- Ouro acumulado é uma base para construções futuras; ainda não pode ser gasto.
- Vitória ao conquistar 80% das células terrestres. Reinicie o servidor para outra partida.
- Jogador eliminado permanece como observador até sair.
- O servidor valida ações, controla economia, combate e propriedade.

## Estado e limites
Mapa esquemático, sem países reais ou fronteiras políticas. Ainda sem cidades, portos, fábricas, tratados, persistência ou matchmaking.
Interface desenha células em ScreenGui; não depende da distância de renderização de peças 3D.
Validação executada: sintaxe Lua 5.4 de ambos os scripts e simulação da lógica de spawn dos seis bots, expansão, custo de tropas, consistência de propriedade e combate.
Ainda é necessário testar UI, toque, desempenho e multiplayer dentro do Roblox Studio. A simulação local não substitui testes no motor Roblox.

Referência técnica: https://create.roblox.com/docs/scripting/events/remote
