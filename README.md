# Mundial War — Alpha 0.2

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
- Cidade (500 ouro): +30 tropas/s e +2.000 de capacidade.
- Fábrica (700 ouro): +35 ouro/s.
- Bunker (400 ouro): dobra o custo de conquista da sua célula.
- Selecione uma construção e toque em uma célula sua vazia; selecione o mesmo botão para voltar ao modo ataque.
- Construções capturadas passam a beneficiar o novo dono. Bots também constroem.
- Ao tocar em território, um aviso mostra dono, tropas e quantidade de células.
- Vitória ao conquistar 80% das células terrestres. Reinicie o servidor para outra partida.
- Jogador eliminado permanece como observador até sair.
- O servidor valida ações, controla economia, combate e propriedade.

## Estado e limites
Mapa esquemático, sem países reais ou fronteiras políticas. Ainda sem portos, tratados, persistência ou matchmaking. Como ainda não há transporte naval, continentes separados limitam a conquista; a meta de 80% permanece provisória.
Interface desenha células em ScreenGui; não depende da distância de renderização de peças 3D.
Validação executada: sintaxe Lua 5.4 de ambos os scripts e simulação da lógica de spawn dos seis bots, expansão, custo de tropas, consistência de propriedade e combate.
Ainda é necessário testar UI, toque, desempenho e multiplayer dentro do Roblox Studio. A simulação local não substitui testes no motor Roblox.

Referência técnica: https://create.roblox.com/docs/scripting/events/remote

## Testes de regressão
Em Linux com Python e liblua5.4: `python tests/test_core.py`.
Alpha 0.2: testes cobrem saldo insuficiente, célula inimiga, construção duplicada, bônus da cidade e fábrica, defesa do bunker, captura de construções e consistência de territórios após 50 rodadas. Lua 5.4 valida o subconjunto Lua usado aqui; não valida APIs Roblox nem aparência da interface.
