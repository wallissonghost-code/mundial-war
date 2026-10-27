# Mundial War — 1.0

Jogo de estratégia territorial mundial em tempo real para Roblox. O mapa-múndi é a tela: você funda uma nação, escolhe quantas tropas enviar, clica duas vezes numa direção e vê a fronteira avançar sozinha, até dominar 80% das terras do planeta.

## Abrir e publicar

- **Studio:** abra `dist/Mundial_War.rbxlx` e clique em Jogar. O arquivo já contém todos os scripts.
- **Rojo:** `rojo serve` usa `default.project.json` (compartilhado em `ReplicatedStorage.MundialWarShared`, servidor em `ServerScriptService.MundialWar`, cliente em `StarterPlayerScripts.MundialWar`).
- **Publicação:** continua manual, pelo Studio. Este repositório não tem workflows, IDs de place/universe nem segredos.
- **Ative em Game Settings → Security: "Enable Mesh / Image APIs"** (no site: Creator Dashboard → Configure → Settings). Sem isso o jogo publicado usa o renderizador de reserva (Frames), que funciona, mas é mais pesado. No Studio o modo rápido funciona direto.
- Defina **Max Players = 55** nas configurações do place (`GameConfig.Match.MaxPlayers` documenta o valor).

## Como se joga

1. Ao entrar, você vê o mundo inteiro. Clique em qualquer terra livre (longe das capitais) para fundar sua capital. A fase de escolha dura 25 s; depois a guerra começa. Quem entra depois ou é eliminado pode fundar uma nova nação.
2. Escolha o percentual de tropas (10/25/50/75/100% ou teclas 1–5).
3. Clique no destino: aparece uma seta da sua fronteira até o ponto. Clique de novo no mesmo lugar para confirmar. A frente avança em leque na direção escolhida, mais larga quanto mais tropas, e as tropas enviadas vão sendo gastas.
4. Terra livre é barata; território inimigo custa conforme a densidade de tropas do defensor, bunkers, metralhadoras e capital. Atacar uma nação neutra declara guerra.
5. Água nunca tem dono. Para cruzar o mar, construa um **porto** e clique numa costa do outro lado: a frota segue a rota pela água e desembarca.
6. Clique com o botão direito (ou toque) numa nação para propor aliança ou declarar guerra. Aliados não podem se atacar.
7. Vence quem controlar 80% das terras. A rodada seguinte começa sozinha.

Câmera: arrastar move, roda do mouse/pinça dá zoom no ponto do cursor, WASD/setas, `F` mostra o mundo, `Espaço` vai para sua capital, `B` abre construções, `Esc` cancela.

## Construções

| | Ouro | Efeito |
|---|---:|---|
| 🏙 Cidade | 1.000 | +25 tropas/s, +15.000 capacidade, +3 ouro/s |
| 🏭 Fábrica | 1.500 | +25 ouro/s; libera tanques e silo |
| ⚓ Porto | 1.200 | Litoral. Frotas de invasão e navios de guerra |
| 🛡 Bunker | 600 | Ataques num raio de 5 custam ×1,8 |
| 🎯 Torre de sniper | 900 | Frentes inimigas no raio 9 perdem 1,5%/s |
| 🔫 Metralhadora | 1.100 | Ataques grandes no raio 6 custam até ×2 |
| 💥 Artilharia | 1.800 | Bombardeia frentes inimigas (raio 14); seus ataques ali custam ×0,8 |
| 🚜 Fábrica de tanques | 2.500 | −8% no custo de ataque (mín. ×0,6) |
| ✈ Base aérea | 3.000 | Ataque aéreo até 90 células (1.200 ouro, recarga 30 s) |
| 📡 Defesa antiaérea | 2.000 | 60% de chance de interceptar mísseis e aviões no raio 14 |
| ☢ Silo nuclear | 6.000 | Míssil nuclear (8.000 ouro, recarga 90 s por silo) |

Cada construção repetida do mesmo tipo custa 35% a mais. Construções capturadas mudam de dono; em terra que vira neutra, são destruídas. Navio de guerra: clique num porto seu (1.500 ouro, até 2 por porto); ataca transportes inimigos que passem a 10 células.

Todos os números estão em `src/shared/GameConfig.lua`.

## Mapa e nações

- Grade de 640 × 320 células (66.822 de terra), projeção Miller, gerada de **Natural Earth 1:50m** (domínio público): 231 países com tamanhos proporcionais, ilhas e arquipélagos. Cada célula conhece seu país.
- Os 36 maiores países viram nações de IA nascendo na própria capital real; 20 tribos fracas ocupam outros países. A IA expande dentro do próprio país, fecha bolsões, ataca vizinhos mais fracos, defende, recua, constrói e usa portos.
- Regerar: `python tools/generate_map.py` (lê `data/naturalearth/`, escreve `src/shared/MapData.lua` e `data/world-map.json`).

## Arquitetura

```
src/shared/   GameConfig, MapData (gerado), MapGrid, Palette, Protocol
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
python3 tests/run_lua.py tests/lua/test_rules.lua tests/lua/test_world.lua tests/lua/test_client.lua
```

Usam a biblioteca Lua 5.4 do sistema (`liblua5.4`), sem Roblox:

- `test_rules`: spawn em terra/água/ocupada, expansão progressiva e conectada, barreira de água, bloqueio de "teletransporte", PvP, alianças, portos e desembarque, nuclear, ataque aéreo e defesa, vitória e nova rodada, validação e limite de comandos.
- `test_world`: mapa real, bots na própria capital, ritmo (2.500 → ~10.000 tropas em 60 s) e desempenho com 5, 10, 20, 30 e 55 nações.
- `test_client`: roda o servidor **e** o cliente reais sobre uma emulação mínima da API Roblox (`tests/lua/roblox_mock.lua`), que serializa remotes como o Roblox, confere escritas no EditableImage e simula cliques, zoom, arraste e teclado. `MW_DUMP=pasta` grava a interface para `tests/render_gui.py` desenhar uma captura aproximada.

**Ainda precisa de teste no Studio:** layout real dos textos e emojis, toque em celular, multiplayer real e o limite de memória do EditableImage em aparelhos fracos. Os testes cobrem regras e integração, não substituem jogar.

## Fora do escopo desta versão

Sons (precisam de assets próprios), trégua/coalizão/transferência de território e persistência entre rodadas.
