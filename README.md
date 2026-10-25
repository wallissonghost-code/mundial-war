# Mundial War — Alpha 0.7

Jogo de conquista territorial para Ghost, em duas versões: Roblox e HTML offline. O HTML é uma partida individual independente, sem conexão com Roblox.

## Abrir

- **Roblox:** abra `dist/Mundial_War_Alpha_0_7.rbxlx` no Studio e inicie Jogar. O arquivo contém os dois scripts, sem depender do place 95206881. Publicação no Roblox continua sendo feita pelo proprietário no Studio.
- **HTML:** baixe `dist/Mundial_War_HTML_0_7.html` e abra em um navegador. Não exige instalação, servidor ou recursos externos. Também há a versão atual em `web/Mundial_War_HTML.html`.
- O projeto Rojo usa `default.project.json`; instalação manual: script servidor em ServerScriptService e LocalScript em StarterPlayerScripts.

## Referência em vídeo — versão 0.7

- Painel flutuante inferior compacto com reserva/capacidade, tropas por segundo, ouro por segundo, percentual de envio e efetivo em avanço.
- Cores de vegetação, areia, montanha e neve sob territórios semitransparentes. Terreno ilustrativo gerado sobre a silhueta existente; não é relevo geográfico real nem a textura do jogo do vídeo.
- Nome e reserva sobre o maior bloco conectado de cada nação. Roblox mostra o avatar da conta; HTML offline usa um emblema com inicial. Nomes de outros jogadores aparecem com zoom.
- Tropas de expedição separadas: iniciar desconta o percentual da reserva uma vez; conquistas consomem o efetivo enviado. Parar ou firmar tratado devolve sobreviventes uma única vez. Ao esgotar o efetivo é preciso enviar outra expedição. Redirecionar contra o mesmo dono usa o efetivo em campo.
- Linhas de rota naval, tooltip no HTML e duplo clique para avançar. No Roblox, seleção e confirmação por Avançar continuam disponíveis.
- Nascimento dos bots afastado das outras capitais; nenhum recurso pago ou loja fictícia.
- Saves 0.7 separados dos saves 0.6: a partida anterior não é apagada nem convertida automaticamente.

## Recursos mantidos

- Expansão por expedição a cada 250 ms, na direção selecionada. O avanço considera alvos acessíveis e que cabem no orçamento; uma defesa cara não bloqueia alvos mais baratos.
- As linhas pretas da referência deixaram de ser canais de água artificiais. A máscara tem 320 × 180 células, 22.043 de terra, e 308 divisões decorativas extraídas da imagem. As divisões são aproximações da ilustração, não fronteiras políticas oficiais.
- Clique seleciona e destaca a célula; Avançar confirma. O marcador na frente mostra as tropas restantes da expedição; a reserva aparece junto ao nome da nação.
- Cidade, fábrica, bunker e porto têm ícones geométricos no mapa e efeitos reais. O painel da seleção explica os efeitos.
- Guerra, aliança de 180 segundos e trégua de 90 segundos. Ataques exigem guerra declarada. Bots podem aceitar ou recusar propostas conforme sua força; jogadores no Roblox precisam aceitar. Tratados mantêm as conquistas e interrompem operações entre os participantes. Aliança pode ser rompida por declaração de guerra; trégua não pode.
- Bots priorizam terras livres, avaliam inimigos mais fracos, constroem e buscam trégua quando pressionados. Portos permitem continuar a conquista entre ilhas.
- Vitória em 80% das terras; derrota ao perder todas. HTML tem pausa, reinício e salvamento automático local a cada cinco segundos, com restauração na próxima abertura. O navegador precisa permitir armazenamento local.
- No Roblox, Reiniciar funciona após vitória ou quando não restarem jogadores humanos vivos; não apaga uma partida ativa de outros jogadores. Não há persistência Roblox nesta versão.

## Construções e combate

| Construção | Ouro | Função |
|---|---:|---|
| Cidade | 500 | +30 tropas/s e +2.000 capacidade |
| Fábrica | 700 | +35 ouro/s |
| Bunker | 400 | Dobra a defesa da célula |
| Porto | 900 | +5 ouro/s e habilita frotas; somente litoral |

Selecione uma construção e clique em célula sua vazia. Clique novamente no botão para sair do modo de construção. Só uma construção por célula; estruturas capturadas passam a beneficiar o novo dono.

Selecione outra terra e use Avançar. O percentual define as tropas enviadas na nova expedição terrestre ou naval. Parar cancela o avanço. Não há passagem terrestre através do oceano; a operação informa quando não há caminho.

Para invadir pelo mar, tenha um porto, selecione a costa de destino e use Invadir. São necessários 250 ouro e ao menos 100 tropas selecionadas. A rota passa somente por água. Uma frota por nação; desembarque custa defesa +50 tropas. Sobreviventes retornam à reserva; se houver tratado com o destino, a frota retorna sem atacar.

## Otimização

O motor mantém listas de fronteira e células por dono, sem varrer o mapa inteiro a cada captura. O Roblox transmite a grade completa na sincronização inicial e depois envia as células alteradas; a interface reutiliza faixas de terreno e atualiza apenas linhas afetadas. O HTML mantém terreno em um canvas de cache, repinta células alteradas e seus vizinhos e limita a pintura da tela a 30 fps quando necessário. A simulação pausa em abas HTML ocultas.

## Gerar e verificar

```sh
python tools/build_release.py
python tests/test_core.py
node tests/test_game.js
node tests/test_ui.js
```

A geração usa apenas Python padrão. Os testes Lua requerem `liblua5.4`; o teste de interface usa `@napi-rs/canvas`. Não são dependências dos arquivos entregues.

`engine/core.lua` e `engine/game.js` contêm as regras, `engine/server_adapter.lua` a conexão Roblox, `web/template.html` e `web/ui.js` a interface web. `tools/trace_reference.py caminho/da/imagem.png` recria a máscara com Pillow, NumPy e SciPy; a imagem original não é necessária para gerar os dois arquivos a partir da máscara já incluída.

Validação executada: sintaxe Lua/JS, expansão e contabilidade, alvos caros/baratos, economia e capacidade, construções, tratados, viagens navais, salvamento/restauração, reinício, derrota, integração da interface HTML com Canvas real e integridade XML do arquivo Roblox. Simulação de 60 segundos no mapa real executada em ambos os motores.

**Limites da verificação:** execução no Roblox Studio, multiplayer, gestos em dispositivos físicos e layout em navegador real ainda precisam de teste. O teste Canvas não substitui a verificação de layout do navegador. Os downloads do Chromium falharam no ambiente de desenvolvimento.
