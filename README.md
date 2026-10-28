# Mundial War — 1.2

Jogo de estratégia territorial mundial em tempo real para Roblox. O mapa-múndi é a tela: você funda uma nação, escolhe quantas tropas enviar, clica numa direção e vê a fronteira avançar sozinha, até dominar 80% das terras do planeta.

## Abrir e publicar

- **Studio:** abra `dist/Mundial_War.rbxlx` e clique em Jogar. O arquivo já contém todos os scripts.
- **Rojo:** `rojo serve` usa `default.project.json` (compartilhado em `ReplicatedStorage.MundialWarShared`, servidor em `ServerScriptService.MundialWar`, cliente em `StarterPlayerScripts.MundialWar`).
- **Publicação:** continua manual, pelo Studio. Este repositório não tem workflows, IDs de place/universe nem segredos.
- **Ative em Game Settings → Security: "Enable Mesh / Image APIs"** (no site: Creator Dashboard → Configure → Settings). Sem isso o jogo publicado usa o renderizador de reserva (Frames), que funciona, mas é mais pesado. No Studio o modo rápido funciona direto.
- Defina **Max Players = 55** nas configurações do place (`GameConfig.Match.MaxPlayers` documenta o valor).

## Modos de jogo

Cada rodada começa com um menu de votação (15 s; termina antes se todos votarem). O modo mais votado vale para a rodada.

- **🌍 Mundial:** funde sua nação em qualquer terra livre e cresça a partir de um ponto. Nações de IA nascem nos 36 maiores países e há 20 tribos.
- **🔥 Conquista Extrema:** todos os países com 6 células ou mais começam ocupados pela IA (cerca de 165). Você clica num país e passa a governá-lo inteiro, com as tropas, o ouro e o petróleo dele. Se sair do jogo, a IA reassume o país. Libera:
  - 🧱 **Muro** (400): alcance 2, ataques ali custam ×3;
  - 🪖 **Trincheira** (700): alcance 4, frentes inimigas perdem 3%/s e você perde metade das tropas ao ceder terreno;
  - 🎆 **Anti-naval** (1.600, litoral): alcance 10, 20 de dano/s em barcos inimigos, desgasta frotas e deixa desembarques ×2 mais caros;
  - 🛩 **Antiaérea de aviões** (1.000): alcance 12, 85% de chance de derrubar aviões (ataque aéreo, fragmentação, bomba de fogo, ponte aérea); não para mísseis do silo;
  - 🛢 **Poço de petróleo** (1.200): +4 petróleo/s; o petróleo paga a ponte aérea, a bomba de fogo e o Fim de Era;
  - 🪂 **Ponte aérea** (base aérea, 500 ouro + 60 petróleo): leva até 4.000 tropas (+2.000 por nível da base) de avião, quase 3× mais rápido que navio, para qualquer terra no alcance;
  - 🔥 **Bomba de fogo** (base aérea, 3.000 ouro + 80 petróleo): incêndio que cresce devagar até 9 células por 30 s, queimando tropas e destruindo construções.

## Como se joga

1. Ao entrar, você vê o mundo inteiro. Clique em qualquer terra livre (longe das capitais) para fundar sua capital. A fase de escolha dura 25 s; depois a guerra começa. Quem entra depois ou é eliminado pode fundar uma nova nação.
2. Escolha o percentual de tropas (10/25/50/75/100% ou teclas 1–5).
3. Clique no destino: o avanço começa na hora, com uma seta da sua fronteira até o ponto. A frente avança em leque na direção escolhida, mais larga quanto mais tropas, e as tropas enviadas vão sendo gastas. (Para voltar à confirmação por dois cliques, use `GameConfig.View.TwoClickConfirm = true`.)
4. Terra livre é barata; território inimigo custa conforme a densidade de tropas do defensor, bunkers, metralhadoras e capital. Atacar uma nação neutra declara guerra.
5. Água nunca tem dono. Para cruzar o mar, construa um **porto** e clique numa costa do outro lado: a frota segue a rota pela água e desembarca.
6. No porto, compre **barcos de defesa**. Clique no barco e depois num ponto da água: ele vai até lá e fica patrulhando em volta. Contra quem está em guerra com você, ele afunda barcos de defesa, destrói frotas de invasão que passam e rouba ouro de portos ao alcance.
7. Clique com o botão direito (ou toque) numa nação para propor aliança ou declarar guerra. Aliados não podem se atacar.
8. Vence quem controlar 80% das terras. A rodada seguinte começa sozinha.

Câmera: arrastar move, roda do mouse/pinça dá zoom no ponto do cursor, WASD/setas, `F` mostra o mundo, `Espaço` vai para sua capital, `B` abre construções, `Esc` cancela.

## Construções

Abra 🏗 e escolha uma construção: o painel diz para que ela serve e o círculo no mapa mostra o alcance onde o cursor está (as defesas que você já tem aparecem em azul). Clique numa construção sua para ver o nível, o que o próximo nível melhora e o botão **Melhorar**. Todas vão do nível 1 ao 5; subir do nível N custa 60% do preço × N.

| | Ouro | Para que serve | Melhora por nível |
|---|---:|---|---|
| 🏙 Cidade | 1.000 | +25 tropas/s, +15.000 capacidade, +3 ouro/s | +15 tropas/s, +10.000 capacidade, +3 ouro/s |
| 🏭 Fábrica | 1.500 | +25 ouro/s; libera tanques e silo | +18 ouro/s |
| ⚓ Porto | 1.200 | Litoral: invasão pelo mar, até 2 barcos de defesa, +6 ouro/s | +1 barco, +5 ouro/s |
| 🛡 Bunker | 600 | Alcance 5: ataques custam ×1,8 | +1 alcance, +0,25 no multiplicador |
| 🎯 Torre de sniper | 900 | Alcance 9: frentes inimigas perdem 1,5%/s | +1,5 alcance, +0,6%/s |
| 🔫 Metralhadora | 1.100 | Alcance 6: ataques grandes custam até ×2 | +1 alcance, +0,25 no teto |
| 💥 Artilharia | 1.800 | Alcance 14: frentes inimigas perdem 3% a cada 2 s; seus ataques ali custam ×0,8 | +2 alcance, +1% de dano, −0,04 no custo |
| 🚜 Fábrica de tanques | 2.500 | Ataques custam −8% (mínimo ×0,6 somando todas) | +3% |
| ✈ Base aérea | 3.000 | Aviões alcançam 90 células | +20 de alcance |
| 📡 Defesa antiaérea | 2.000 | Alcance 14: 60% de chance de derrubar aviões e mísseis | +2 alcance, +8% (máx. 95%) |
| 🚀 Silo de mísseis | 6.000 | Lança EMP, atômica e (nível 3+) hidrogênio | −12% no tempo de recarga |

Cada construção nova do mesmo tipo custa 35% a mais. Construções capturadas mudam de dono e mantêm o nível; em terra que vira neutra, são destruídas.

## Barcos de defesa

1.500 ouro, comprados no porto. 100 de vida, alcance 9 e 14 de dano por segundo, mais fortes conforme o nível do porto onde nasceram. Patrulham em volta do ponto que você escolher (precisa ser água ligada ao porto). Atacam apenas nações com quem você está em guerra.

## Navios de carga (os dois modos)

Cada porto manda navios 🚤 numa rota comercial a cada 30 s (um no mar por nível do porto). Quando o navio volta, você recebe 250 de ouro (+60 por nível do porto). Um barco de defesa em guerra com o dono que chegar perto captura a carga e recebe 1,5× o valor.

## Bombas e ataques

O botão 💣 aparece quando você tem base aérea ou silo. Escolha a arma, clique no alvo (o círculo vermelho mostra a área) e clique de novo para lançar. A defesa antiaérea do alvo pode derrubar qualquer uma.

| | Ouro | Lançador | Efeito |
|---|---:|---|---|
| ✈ Ataque aéreo | 1.200 | Base aérea | Raio 3: destrói construções e mata 6% das tropas do alvo |
| 💣 Fragmentação | 2.500 | Base aérea | Raio 6: mata muitas tropas, sem destruir construções nem território |
| ⚡ EMP | 4.000 | Silo | Raio 12: desliga as construções inimigas por 45 s |
| ☢ Atômica | 8.000 | Silo | Raio 10: destrói construções, mata tropas, centro fica sem dono |
| ☣ Hidrogênio | 20.000 | Silo nível 3 | Raio 18: a maior explosão |
| 🌋 Fim de Era | 50.000 (+400 petróleo na Extrema) | Silo nível 5 | Ogivas no alvo e nas capitais de até 4 outros inimigos em guerra com você; cada uma destrói, mata tropas, deixa fogo e um EMP de 60 s. Nenhuma antiaérea para |

Todos os números estão em `src/shared/GameConfig.lua`; as contas de nível ficam em `src/shared/BuildingStats.lua`.

## Mapa e nações

- Grade de 640 × 320 células (66.822 de terra), projeção Miller, gerada de **Natural Earth 1:50m** (domínio público): 231 países com tamanhos proporcionais, ilhas e arquipélagos. Cada célula conhece seu país.
- Os 36 maiores países viram nações de IA nascendo na própria capital real; 20 tribos fracas ocupam outros países. A IA expande dentro do próprio país, fecha bolsões, ataca vizinhos mais fracos, defende, recua, constrói e usa portos.
- Regerar: `python tools/generate_map.py` (lê `data/naturalearth/`, escreve `src/shared/MapData.lua` e `data/world-map.json`).

## Arquitetura

```
src/shared/   GameConfig, BuildingStats, MapData (gerado), MapGrid, Palette, Protocol
src/server/   init.server (bootstrap) · World (agenda) · NetworkService (Roblox)
              TerritoryService · NationService · EconomyService · ExpansionService
              CombatService · BuildingService · NavalService · StrategicService
              DiplomacyService · BotService · MatchService · CommandService
src/client/   init.client · ClientState · MapRenderer · CameraController
              OverlayRenderer · InputController · HUD · DebugOverlay
```

- **Servidor autoritativo.** O cliente só envia intenções; `CommandService` valida tipo, faixa, posse, rota terrestre, aliança, ouro, recarga e aplica limite de 10 comandos/s.
- **Território** em vetores por célula com conjuntos de posse e fronteira por nação; nenhuma captura varre o mapa. Água é recusada no único ponto que muda posse.
- **Rede:** o mapa está no cliente; na entrada vai só a posse comprimida. Depois, mudanças em lote a cada 0,2 s, números das nações a cada 1 s, frentes a cada 0,4 s e dados privados só para o dono.
- **Renderização:** um pixel por célula num único `EditableImage`, repintando só a área alterada. Não depende de Parts nem da qualidade gráfica. Rótulos, ícones e setas ficam numa camada que acompanha o zoom com 3 níveis de detalhe.
- **Desempenho medido** (Lua 5.4, 120 s simulados): 5 a 55 nações custam ~0,2–1,1 ms por passo de 0,1 s. A análise de território é dividida entre passos.
- `GameConfig.DEBUG_MODE = true` mostra célula, país, chunk, dono, ordens e estado dos bots.

## Testes

```sh
python3 tests/run_lua.py tests/lua/test_rules.lua tests/lua/test_world.lua tests/lua/test_modes.lua tests/lua/test_client.lua
```

Usam a biblioteca Lua 5.4 do sistema (`liblua5.4`), sem Roblox:

- `test_rules`: spawn em terra/água/ocupada, expansão progressiva e conectada, barreira de água, bloqueio de "teletransporte", PvP, alianças, portos e desembarque, níveis das construções, barcos de defesa (combate, patrulha, roubo de ouro), todas as bombas, defesa antiaérea, vitória e nova rodada, validação e limite de comandos.
- `test_world`: mapa real, bots na própria capital, ritmo (2.500 → ~10.000 tropas em 60 s) e desempenho com 5, 10, 20, 30 e 55 nações.
- `test_modes`: votação, tomada de país na Conquista Extrema (165 países), muro, trincheira, anti-naval, petróleo, ponte aérea, bomba de fogo, antiaérea de aviões, Fim de Era e navios de carga com captura.
- `test_client`: roda o servidor **e** o cliente reais sobre uma emulação mínima da API Roblox (`tests/lua/roblox_mock.lua`), que serializa remotes como o Roblox, confere escritas no EditableImage e simula cliques, zoom, arraste e teclado. `MW_DUMP=pasta` grava a interface para `tests/render_gui.py` desenhar uma captura aproximada.

**Ainda precisa de teste no Studio:** layout real dos textos e emojis, toque em celular, multiplayer real e o limite de memória do EditableImage em aparelhos fracos. Os testes cobrem regras e integração, não substituem jogar.

## Fora do escopo desta versão

Sons (precisam de assets próprios), trégua/coalizão/transferência de território e persistência entre rodadas.
