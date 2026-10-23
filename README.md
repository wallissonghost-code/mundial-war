# Mundial War — Alpha 0.5

Jogo de conquista territorial para Roblox. Esta versão usa a silhueta da imagem fornecida pelo usuário, em proporção 16:9: continentes, ilhas e faixa da Antártida seguem a ilustração, não uma projeção cartográfica oficial.

## Abrir no Studio
Execute python tools/build_place.py e abra dist/Mundial_War_Alpha_0_5.rbxlx em Arquivo → Abrir do arquivo; depois Jogar.
Também é possível usar default.project.json com Rojo, ou instalar src/server.server.lua em ServerScriptService e src/client.client.lua como LocalScript em StarterPlayerScripts.
Não há publicação automática GitHub → Roblox configurada.

## Mapa e visual
- 320 × 180 = 57.600 células; 20.699 terrestres.
- Terra neutra cinza-claro uniforme, contornos escuros e mar azul com faixas de litoral.
- Silhueta extraída da referência do usuário em data/reference-mask.json.
- Regiões internas são divisões decorativas geradas para o jogo, não uma cópia exata das divisões desenhadas nem fronteiras políticas oficiais.
- Zoom até 10×; mapa começa inteiro na tela. Células seguem a cor do dono após conquista.
- Geração da interface em etapas e agrupamento das atualizações recebidas durante a inicialização.
- Data/land.geojson preserva a fonte Natural Earth de versões anteriores; não é usada na silhueta atual.
- Para regenerar: python tools/generate_map.py; python tools/build_place.py.

## Jogabilidade
Escolha terra sem dono. Toque em território vizinho para expandir ou atacar continuamente; Parar cancela a operação terrestre.
Percentual limita gasto por rodada terrestre e determina tropas enviadas numa frota.
Cidade: 500 ouro, +30 tropas/s e +2.000 capacidade. Fábrica: 700 ouro, +35 ouro/s. Bunker: 400 ouro, dobra defesa da célula.
Porto: 900 ouro, exige litoral e gera +5 ouro/s.
Selecione uma construção e toque em célula sua vazia; selecione o mesmo botão para desativar.
Para navegar: porto próprio, Invadir mar, destino costeiro acessível pela água; custa 250 ouro e mínimo de 100 tropas. Uma frota por nação.
Desembarque custa defesa +50 tropas. Sobreviventes retornam; derrota destrói frota e causa baixas de metade do efetivo ao defensor. Eliminação ou saída cancela a frota.
Seis bots expandem, constroem e navegam. Vitória com 80% das terras; reinicie o servidor para nova partida.

## Validação e limites
python tests/test_core.py (Python + liblua5.4 em Linux).
Testes: construções, economia, conquista, navegação, recursos inválidos, tempo de viagem, captura, eliminação, dimensões e amostras da silhueta.
Arquivo XML validado com os scripts nas posições corretas.
Ainda é necessário testar execução, UI, toque, multiplayer e desempenho no Roblox Studio. Não há tratados, persistência ou fronteiras políticas.
