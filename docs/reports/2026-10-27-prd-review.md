# Revisão técnica do PRD do OpenWifi contra os spikes (2026-10-27)

Esta é uma revisão crítica. Ela compara o PRD (`docs/PRD.md`, versão 1.0 de 25/10/2026) com os dois relatórios de spike do dia:

- **A1**: `2026-10-27-spike-latency-traffic.md` (latência e tráfego).
- **A2**: `2026-10-27-spike-discovery.md` (descoberta de dispositivos).

Regras desta revisão:

- Todo número vem do PRD ou de um spike.
- Quando eu raciocino além da evidência, digo que é **inferência**.
- Nenhuma fonte externa nova foi aberta. Onde falta fonte oficial, está escrito "não verificado".
- Os spikes rodaram em uma única máquina: macOS 27.2, Apple Silicon (arm64), Ethernet e Wi-Fi ao mesmo tempo, uma rede doméstica /24 (A1 e A2, cabeçalhos).
- O PRD propõe macOS 14 ou superior (PRD, cabeçalho). **Nada foi medido em macOS 14.**

## 1. Veredito geral

- A parte "medir o próprio Mac" funciona sem root: latência (ICMP e TCP), tráfego (64 bits) e gateway. Tem ressalvas de sandbox e de offsets não documentados.
- A parte "descobrir outros aparelhos" funciona só para **IP e presença**. O app não recebe MAC de ninguém (A2 §1), então fabricante, identidade por MAC e MAC no detalhe caíram.
- O nome vem quase só do Bonjour. O DNS reverso não entregou nada (A2 §4).
- O PRD acertou ao dizer que dados por aparelho dependem do roteador. O roteador testado não oferece nenhum caminho local passivo (A2 §7), então a Fase 3 (RF-12 a RF-14) continua sem base.
- O maior risco que ninguém testou: um `.app` assinado, com a permissão de Rede Local concedida ou negada. Hoje a conclusão "MAC indisponível" vale só para o caso sem essa permissão ter sido exercitada (A2 §1, §3 e "Decisões" item 5).

## 2. Status por requisito

Legenda: **Confirmado** = medido e funciona. **Com ressalva** = funciona, mas com limite medido. **Quebrado** = a premissa do PRD falhou. **Não testado** = nenhum spike tocou.

| ID | Status | Evidência em uma linha | Esqueleto cobre? |
|---|---|---|---|
| RF-01 ícone na barra com painel | Não testado | Nenhum spike abriu `MenuBarExtra` nem `LSUIElement`. | Sim, UI com mocks (`OpenWifi/App`, `UI/Popover`); sem validação real. |
| RF-02 reagir a interface e gateway | Com ressalva | Gateway e interface via SCDynamicStore: funciona (A1 §1). `NWPathMonitor` só lido na doc, nada simulado (A1 §5). Duas rotas default, en0 e en1, ao mesmo tempo (A1 §1). | Só a porta `NetworkPathObserver` e um mock. |
| RF-03 latência gateway e externo | Com ressalva | ICMP sem root: 10/10 respostas, mesma ordem de grandeza do `ping` (A1 §2). TCP funciona, com 1 a 4 ms a mais de overhead (A1 §3). Em sandbox, ICMP exige `network.server` (A1 §6). | Porta `LatencyProbe`, `LatencyWindow`, `ProbeMethod` e testes. Sonda real não existe. |
| RF-04 detectar dispositivos da /24 | Com ressalva | Varredura de 254 IPs em ~190 ms de envio e 0,5 a 1,7 s no total; 6 hosts resolvidos (A2 §2). Não há lista de referência do roteador, então a cobertura real é desconhecida (A2 §2, última linha). | Porta `DeviceDiscovery` e mock. |
| RF-05 nomes por mDNS e DNS reverso | Com ressalva (DNS reverso quebrado) | Bonjour funciona e traz TXT (A2 §3). `getnameinfo`: 0 de 7. mDNS PTR: 2 de 7, e um dos dois é o próprio Mac (A2 §4). | `displayName` opcional no modelo; sem resolvedor. |
| RF-06 histórico de presença | Com ressalva | O corte `stale` após 3 varreduras é compatível com a expiração ARP de 1200 s (A2 §2). A identidade entre trocas de IP é fraca sem MAC (A2 §6). | `PresenceTracker` e testes; sem persistência. |
| RF-07 tráfego do Mac | Com ressalva | 64 bits via `IFMIB_IFDATA`, igual ao `netstat -ib` byte a byte. `NET_RT_IFLIST2` e `getifaddrs` vêm truncados em 32 bits (A1 §4). Offsets não documentados. | `TrafficRateCalculator` com `counterBits`. Sampler real não existe. |
| RF-08 preferências | Não testado | Fora dos spikes. | Não. |
| RF-09 gráfico de 24 h | Não testado | Depende de SQLite e Swift Charts, ambos fora dos spikes. | Só `LatencyWindow` em memória. |
| RF-10 alertas | Não testado | Fora dos spikes. | Não. |
| RF-11 iniciar no login | Não testado | `SMAppService` não foi exercitado. | Não. |
| RF-12 adaptadores de roteador | Com ressalva (SSDP quebrado) | SSDP/UPnP: 0 respostas, 3 portas de descrição recusadas (A2 §7). O resto da integração não foi tocado. | Protocolo `RouterAdapter` e modelos, sem implementação. |
| RF-13 consumo por dispositivo | Não testado | O IGD teria só totais WAN, não por cliente, e isso é doc UPnP, não observado (A2 §7). | Modelos `RouterTrafficSample`. |
| RF-14 nó Mesh e tempo de associação | Não testado | Nenhuma fonte encontrada (A2 §7). | Modelo `RouterCapabilities`. |
| RF-15 exportar inventário | Não testado | Fora dos spikes. | Não. |
| PRD §5.6 MAC no detalhe do dispositivo | Quebrado | MAC vem mascarado como `02:00:00:00:00:00` em todos os 6 hosts e 14 de 14 entradas IPv6 (A2 §1, §1b). | `macAddress` é opcional, o que acomoda. |
| PRD §5.6 fabricante por OUI | Quebrado | Sem MAC real não há chave de busca (A2 §5). | Não implementado. |

Requisitos não funcionais (PRD §12) que os spikes tocaram:

| Meta | Status | Evidência |
|---|---|---|
| Resiliência: sleep/wake, troca de rede, perda de gateway | Não testado | A1 "Fora do escopo": troca real de rede e disparo do `NWPathMonitor` não foram feitos. |
| Rede: scans limitados à rede autorizada | Com ressalva | Lotes de 32 envios com 20 ms entre lotes funcionam (A2 §2). Sem sandbox, a varredura tem de ser por interface (`IP_BOUND_IF`), senão dá `EHOSTUNREACH` (A2 §2). |
| Inicialização, CPU, memória, energia | Não testado | O PRD já diz que são hipóteses (§12, última linha). Nenhum spike mediu. |
| Idiomas, acessibilidade | Não testado | Fora dos spikes. |
| Testes: regras de presença, RTT/perda, bytes | Parcial | 28 testes passam no esqueleto, só sobre lógica pura com dados fabricados. Nenhum teste toca um socket real. |

## 3. Premissas do PRD que os spikes derrubaram ou enfraqueceram

| Premissa | O que o PRD diz | O que foi medido | Consequência |
|---|---|---|---|
| `NeighborTableReader` via sysctl | §8 componentes e §9: "tabela de vizinhos ARP/IPv6". §7: "ARP/neighbor cache". | IPv4: 0 bytes nas 3 execuções, mesmo com `arp -an` listando 23 linhas. IPv6: entradas vêm, mas com MAC mascarado (A2 §1). O gate é "binário da plataforma Apple", não entitlement nem permissão de Rede Local (A2 §1). | O componente precisa ser redesenhado como "verificador de host resolvido" via `RTM_GET` por IP (A2 §1b). Ele devolve IP e "confirmado", nunca MAC. Isso é comportamento observado: A2 admite que não achou documentação Apple (A2 §1). |
| MAC no detalhe do dispositivo | §5.6: "MAC (quando acessível)". §8 modelo: `macAddress: String?`. | Mascarado em todos os casos testados (A2 §1, §1b). | O "quando acessível" do PRD virou "quase nunca no caminho nativo". A UI deve mostrar "MAC indisponível neste sistema" e não um campo vazio sem explicação. |
| Fabricante por OUI | §5.6: "fabricante inferido se houver base local". | Sem MAC não há entrada. A lista IEEE existe (40.421 linhas), mas o app não tem o dado para consultar (A2 §5). Licença de redistribuição não confirmada. | Cortar do MVP. Reabrir só se o MAC vier por `arp`. |
| DNS reverso | RF-05: "mDNS/Bonjour e DNS reverso". | `getnameinfo` 0 de 7. mDNS PTR 2 de 7, sendo 1 o próprio Mac, então 1 de 6 aparelhos de outros (A2 §4). O relatório diz "~29%", o que infla a taxa porque inclui o próprio Mac. | Remover "DNS reverso" do critério de aceite. Nome vem do Bonjour; DNS reverso é tentativa barata, não requisito. |
| SSDP/UPnP no roteador | §10 pergunta por interface local documentada (spike obrigatório, passos 2 e 3). | 0 respostas SSDP em en0, en1 e unicast; descrições UPnP recusadas (A2 §7). | Nada de fingerprint grátis. O adapter, se existir, dependerá de credencial ou de outra interface local ainda não identificada. |
| Contadores de 32 bits | §9: "tratar reset/troca de interface e rollover". | Nesta versão do macOS, a API mais usada (`NET_RT_IFLIST2`) e `getifaddrs` truncam em 32 bits; a 25 MB/s isso estoura em ~170 s (A1 §4). | O PRD acertou em prever rollover, mas errou em tratá-lo como detalhe. É o caminho padrão, a menos que o `IFMIB_IFDATA` (offsets não documentados) seja validado. |
| ICMP sem privilégio | §9, última linha: "requer spike". | Funciona como uid 501 (A1 §2). Em sandbox, a resposta só chega com `network.client` mais `network.server` (A1 §6). | Resolvido para build sem sandbox. Para a loja, vira risco de revisão (§4 abaixo). |
| `NWPathMonitor` para mudança de rota | §8 conectividade; RF-02. | Só doc; a doc lida não diz quais mudanças disparam, e `gateways` não indica o primário (A1 §5). | Usar só como gatilho. A fonte da verdade do gateway é o SCDynamicStore (A1 §1). |
| Uma rede ativa por vez | Implícito em §5.1 "interface ativa" e RF-07 "interface do Mac". | O Mac de teste tem en0 (Ethernet) e en1 (Wi-Fi) na mesma /24, com duas rotas default (A1 §1) e 8 hosts resolvidos em en1 contra 6 em en0 (A2 §2). | A UI e o modelo de dados precisam decidir: tráfego da interface primária ou soma das ativas; descoberta e histórico por interface. O PRD não decide isso. |
| Presença por cache ARP | §9: `stale` após 3 varreduras. | A entrada ARP vive 1200 s (A2 §2). A varredura de 60 a 120 s fica bem abaixo disso. | **Inferência**: um aparelho que sumiu pode continuar "resolvido" no `RTM_GET` por até 20 minutos. Não foi testado (A2 §2: "não simulei aparelhos desligados"). A presença precisa de evidência ativa (resposta ICMP ou Bonjour), não só `RTM_GET`. |

## 4. O que é difícil de verdade (risco x esforço)

Ordem de cima para baixo, do mais arriscado ao menos. Cada item traz o caminho recomendado e o plano B mais barato.

### 4.1 Distribuição fora da App Store e notarização

- **Fato (A1 §6, A2 §1):** o que o produto quer (ICMP, `arp`) fica mais fácil sem App Sandbox. ICMP exige `network.server` com sandbox, e `arp` é shell-out. Distribuição por Developer ID, sem sandbox, "não tem essa restrição" (A1 §6).
- **PRD §11** já diz "GitHub Releases, com assinatura/notarização quando disponíveis" e "não prometer Mac App Store no MVP". O PRD está certo, mas "quando disponíveis" é fraco.
- **Recomendação (inferência):** tratar Developer ID mais notarização como caminho oficial do MVP, decidido já. Notarização exige conta paga de desenvolvedor Apple; a decisão é do dono (§7). A Mac App Store fica como possibilidade futura.
- **Plano B barato:** build local (`xcodebuild`) com instruções no README, que o PRD já prevê (§11), e que não depende de nenhuma conta.
- **Não verificado:** processo e requisitos exatos de notarização; nenhuma página da Apple foi aberta nesta revisão.

### 4.2 Identidade de dispositivo sem MAC

- **Evidência (A2 §6):** o app vê IP, nome de instância Bonjour e chaves TXT. Alguns aparelhos Apple publicam identificador estável: `deviceid` e `rpBA` (formato de MAC), `identifier` (formato UUID).
- **Limite:** a maioria dos aparelhos de IoT e TVs em espera não tem Bonjour e fica só com IP (A2 §6).
- **Recomendação:** identidade em três níveis, como A2 §6 propõe. Forte: UUID/`deviceid` do TXT. Médio: nome da instância estável por N varreduras. Fraco: IP.
  - Guardar o nível junto com o dispositivo.
  - A UI mostra "provável o mesmo aparelho" quando só o nome bate.
  - Aparelho só com IP é registrado como "sem identidade estável": nunca promover IP a identidade.
- **Alinha com o princípio "honestidade dos dados"** (PRD §2): identidade vira dado inferido, com rótulo.
- **Atenção:** `deviceid` do AirPlay "costuma ser o MAC de Wi-Fi", mas isso é convenção do protocolo, não verificada contra o MAC real (A2 §6). Não tratar como MAC.
- **Plano B barato:** sem identidade além de IP e nome. O histórico por aparelho fica fragmentado quando o IP muda. Isso precisa ser dito na UI.

### 4.3 Obter MAC real: `arp` por shell-out versus sandbox

- **Única via testada com MAC real (A2 §1):** `/usr/sbin/arp -an`, binário de plataforma, sem root.
- **Custos:**
  - Conflita com o critério "sem runtime externo" só na letra: é binário do próprio sistema.
  - Conflita com App Sandbox. A2 afirma "incompatível com App Sandbox", mas isso não foi testado nos spikes (**sub-evidenciado**; só o caso sem sandbox foi executado).
  - Cria dependência do formato de saída do `arp`, que pode mudar entre versões do macOS.
  - Entrega MAC aleatório (Wi-Fi privado) que muda por rede, sem ajudar na identidade (A2 §5).
- **Recomendação:** `ArpMacReader` atrás de um protocolo, desligado por padrão, existente apenas no build sem sandbox. A UI diz "MAC obtido via `arp` do sistema". Se ligado, o MAC entra como evidência de identidade nível forte, mas o app nunca depende dele.
- **Plano B barato:** não implementar. O produto já é útil sem MAC (IP, nome Bonjour, presença).
- **Privacidade:** guardar MACs é guardar identificador de pessoas no banco local. O PRD §11 limita retenção a 30 dias; incluir MAC nessa regra e no "apagar histórico".

### 4.4 ICMP mais o entitlement `network.server`

- **Medido (A1 §6):** em `.app` assinado ad-hoc com sandbox, `recv()` do ICMP falha com `errno=1` usando só `network.client` (3 de 3 e 2 de 2 tentativas). Funciona com `network.client` mais `network.server` (3 de 3).
- **Sub-evidência:**
  - Poucas amostras e assinatura ad-hoc, não Developer ID.
  - A doc oficial não cobre o caso (A1 §6 diz "unverified").
  - O fórum citado (thread 775253) não foi lido por completo (A1 §6).
  - Nada foi dito sobre revisão da App Store.
- **Recomendação:** o plano de distribuição fora da loja (4.1) elimina o problema. Sandbox só entra se o dono quiser a loja; nesse caso, o TCP fallback precisa estar pronto e rotulado "RTT TCP" desde o primeiro dia (PRD §14: "sem rótulos enganosos").
- **Plano B barato:** TCP em 443, 80 e 53 como A1 §3 e §"Decisão" sugerem. Observação: o RTT TCP não é ping, e o primeiro estado terminal deve ser usado (A1 §3).

### 4.5 Validação dos offsets do contador na inicialização

- **Risco (A1 §4):** `ifibytes` em +116 e `ifobytes` em +124 do `ifmibdata`, medidos só em arm64 e só nesta versão do macOS, e não documentados pela Apple.
- **Lacuna do PRD:** o PRD propõe macOS 14 ou superior. Nem layout nem truncamento foram testados em outra versão. Em Mac Intel, os offsets são desconhecidos.
- **Recomendação:** na inicialização e a cada troca de interface, fazer a validação cruzada abaixo; qualquer divergência rebaixa para `getifaddrs` com `counterBits = 32` e rótulo "estimado". O sampler nunca acusa 64 bits sem a prova.
  1. Ler `getifaddrs` (A), depois `IFMIB_IFDATA`, depois `getifaddrs` (B).
  2. Aceitar se os 32 bits baixos do IFMIB ficam entre A e B, levando em conta o wrap em 2^32. Comparar com igualdade exata seria errado: o tráfego avança entre as leituras.
  3. Validar rx e tx separadamente.
- **Falha provável do esqueleto, inferência:** `TrafficRateCalculator` aceita um único wrap de 32 bits se a taxa implícita couber em 500 MB/s (`OpenWifi/Monitoring/Logic/TrafficRateCalculator.swift`). Depois de sleep ou pausa longa com contador de 32 bits, mais de um wrap pode ter ocorrido e o delta sai errado, mas plausível. Falta um limite de intervalo máximo entre amostras (descartar a amostra, como o esqueleto já faz para reset).
- **Plano B barato:** só `getifaddrs` com amostragem a cada 1 a 2 s (PRD §9), descartando amostras após intervalo grande.

### 4.6 Fluxo de permissão de Rede Local em `.app` assinado real

- **Nunca testado.** O spike só deixou os plist keys no `.app` sem fazer operação de rede local, e nenhum prompt apareceu (A2 §3). Negar, conceder e reler exige o dono (A2 "Decisões" item 5).
- **O que se sabe, por doc (TN3179, citada em A2 §3):** a permissão existe a partir do macOS 15; ferramentas de linha de comando abertas do Terminal são liberadas automaticamente. Isso explica por que todos os spikes rodaram sem prompt, e **por isso nenhum resultado de A2 prova o comportamento do `.app` final**.
- **Perguntas abertas, todas não verificadas:**
  - O gateway (alvo local) também exige a permissão para o ICMP de RF-03?
  - A permissão muda a máscara de MAC? O A2 levantou a hipótese e não testou.
  - Qual é a mensagem de erro quando negada? A2 §3 afirma que o browse "falha com política negada em vez de mostrar vazio", sem citar a origem: tratar como não verificado.
  - Em macOS 14, não há o prompt (disponível "desde macOS 15").
- **Recomendação:** antes de qualquer UI de descoberta, um teste manual com o dono em `.app` Developer ID ou Apple Development. Roteiro: conceder, medir, negar, medir de novo. Modelar um estado explícito "permissão de rede local negada" na UI, em vez de uma lista vazia.
- **Plano B barato:** quando negada, manter só latência de internet e tráfego do Mac, e mostrar "descoberta indisponível: permissão negada".

### 4.7 Tráfego por dispositivo sem telemetria do roteador

- **Fato (PRD §7, §3):** banda e consumo de outros aparelhos não estão disponíveis sem roteador, espelhamento ou monitor no caminho. Os spikes não encontraram contraexemplo.
- **Recomendação:** manter fora do MVP, como o PRD já faz. O erro seria "estimar" por contagem de pacotes de sondagem ou similar: isso quebra "honestidade dos dados".
- **UI:** linha "Consumo por aparelho: indisponível sem dados do roteador". Nunca mostrar zero.
- **Plano B barato:** nenhum, e é correto não ter. Se o dono quiser o dado, só um adapter de roteador resolve (4.8).

### 4.8 Viabilidade do adapter de roteador

- **O que foi tentado (A2 §7):** SSDP multicast e unicast, e 2 URLs UPnP padrão. Resultado: zero respostas e conexões recusadas.
- **Lacuna:** nenhum spike identificou qual aparelho é o `.1` (EX520 ou AX53), firmware, nem se existe interface local de leitura. Os passos 1 a 6 de PRD §10 não foram feitos. A2 §7 chama o gateway de "TP-Link (EX520/AX53)" sem prova de modelo: **sub-evidenciado**.
- **Fato (A1 §3):** o gateway aceita conexão TCP na porta 80, ou seja, há alguma interface web local. O A2 deliberadamente não tocou nela (A2 §7).
- **Recomendação:**
  - Adiar para M3, como o PRD §13 já diz, e reabrir como spike próprio, com autorização do dono, antes de qualquer código.
  - Candidatos a testar são hipóteses, não verificados: UPnP ativado pelo dono, interface web local, SNMP.
  - Cada um precisa de evidência de campos reais, com login só se o dono autorizar.
- **Plano B barato:** nenhum adapter. RF-12 a RF-14 aparecem como "indisponível" (PRD já permite, §10).

## 5. Spike claims que parecem sub-evidenciados

| Onde | Claim | Problema |
|---|---|---|
| A1 §5 | `NWPathMonitor` funciona | Só doc. Marcado como "WORKS-WITH-CAVEAT" no resumo, mas nada foi executado. Deveria constar como "não testado". |
| A1 §6 | Sandbox só com `network.server` | Amostra pequena, assinatura ad-hoc, doc Apple silenciosa. O fórum 775253 não foi lido por completo. |
| A1 §3 | Snippet TCP | O próprio relatório diz que não foi compilado literalmente. |
| A1 §2 | ICMP "mesma ordem de grandeza" | 1.1.1.1: média 13,20 ms contra 15,386 ms do `ping`, diferença de ~2 ms. Explicação ("jitter") não foi demonstrada. |
| A1 §4 | Offsets +116 e +124 | Uma máquina, uma arquitetura, uma versão do macOS. |
| A2 §1 | "Gate é binário de plataforma" | Inferido de um único contraste (`/usr/bin/python3` contra os demais). Nenhuma doc Apple. A2 admite. |
| A2 §1 | "Local Network não é o gate" | Raciocínio por exclusão: o CLI no Terminal tem a permissão automática. Não prova nada sobre `.app` com a permissão concedida. |
| A2 §1 e §6 | "arp incompatível com sandbox" | Não foi executado dentro do sandbox. |
| A2 §2 | Cobertura "4 outros dispositivos" | Sem lista de verdade do roteador. A2 §2 comenta "casa maior", ou seja, provável subcontagem. 6 de 6 hosts respondem ICMP: não se sabe quantos aparelhos silenciosos existem. |
| A2 §2 | ICMP com checksum calculado "pelo app" | A1 §2 mostra que o kernel recalcula. Inconsistência entre os dois relatórios; sem impacto prático. |
| A2 §3 | Chamadas de A2 no sandbox | `PF_ROUTE` (`RTM_GET`), `DNSService*`, `IP_BOUND_IF` e UDP de varredura nunca foram testados em sandbox. A1 §6 só cobriu SCDynamicStore, sysctl, NWConnection e ICMP. |
| A2 §4 | DNS reverso "~29%" | Inclui o próprio Mac; real: 1 de 6. |
| A2 §6 | `deviceid` e `rpBA` como identificadores estáveis | Estabilidade entre dias, reinícios e Wi-Fi privado não foi medida; só se viu o formato. |

## 6. Mudanças recomendadas no PRD

Todas são **sugestão minha, não aprovada**. O PRD é documento do dono: nada foi editado.

| # | Seção | Texto atual | Texto proposto |
|---|---|---|---|
| 1 | §3 objetivo 2 | "exibir IP, nome (quando disponível) e status estimado" | Manter. Acrescentar: "sem MAC no caminho nativo; MAC é opcional via `arp` do sistema, apenas no build sem sandbox." |
| 2 | §5 Popover, item 5 | "MAC (quando acessível), fabricante inferido se houver base local, primeiro/último visto e histórico" | "Nível de identidade (forte, médio, fraco), nome e origem do nome, primeiro/último visto e histórico. MAC e fabricante só quando obtidos por `arp` opcional." |
| 3 | §6 RF-05 | "Resolver nomes por mDNS/Bonjour e DNS reverso" | "Resolver nomes por Bonjour (TXT incluído) e mDNS PTR; DNS reverso é tentativa não confiável." Critério: "Mostra IP quando não há nome." |
| 4 | §6 RF-04 critério | "dispositivos encontrados por descoberta suportada" | Acrescentar: "por interface ativa, com 'descoberta limitada' quando a permissão de rede local é negada." |
| 5 | §7 matriz | Linha "IP, nome e presença: ARP/neighbor cache, Bonjour, DNS e sondagem" | "Varredura UDP/ICMP por interface mais `RTM_GET` por IP, Bonjour e mDNS PTR." Nova linha: "MAC de outros aparelhos: não disponível no caminho nativo (macOS 27.2); opcional via `arp -an`." |
| 6 | §8 componentes | `NeighborTableReader` | Renomear para `HostResolutionChecker` (via `RTM_GET`). Acrescentar `IdentityResolver` e, opcional, `ArpMacReader`. |
| 7 | §8 stack, conectividade | "`NWPathMonitor` para mudanças de rota" | "`SCDynamicStore` como fonte do gateway e da interface primária; `NWPathMonitor` apenas como gatilho." |
| 8 | §8 modelo | `macAddress: String?`; `presence`; `source` | Acrescentar `identityLevel` e `interfaceName`. Comentar que o MAC é raro. |
| 9 | §9 latência | "ICMP sem privilégios requer um spike" | "ICMP DGRAM sem root funciona; id aleatório, filtrar por id e seq; sem rota aparece como erro de `sendto`. Fallback TCP rotulado." |
| 10 | §9 tráfego | "calcular delta de bytes ... rollover" | "Usar `IFMIB_IFDATA` (64 bits) com validação cruzada na inicialização; senão `getifaddrs` (32 bits) com descarte de amostras após intervalo grande." |
| 11 | §9 presença | "`stale` após 3 varreduras sem confirmação" | "Confirmação exige resposta ICMP ou Bonjour; `RTM_GET` sozinho é pista, não prova (a entrada ARP vive 1200 s)." |
| 12 | §11 distribuição | "GitHub Releases, com assinatura/notarização quando disponíveis" | "Developer ID mais notarização é o caminho oficial do MVP; Mac App Store fica fora até decisão sobre `network.server`." |
| 13 | §11 permissões | "Incluir `NSLocalNetworkUsageDescription`; configurar `NSBonjourServices`" | Acrescentar a lista fixa de tipos (A2 §3) e o estado "permissão negada". |
| 14 | §12 | Meta "macOS 14 ou superior" | "Versão mínima só após testes em essa versão; hoje testado apenas em macOS 27.2 arm64." |
| 15 | §13 M0 | Saídas de M0 | Marcar o que está feito (latência, tráfego, descoberta no CLI) e o que falta (`.app` assinado, permissão, sandbox para `PF_ROUTE`, troca de rede). |
| 16 | §14 | Critérios de aceite | Novos: "MAC ausente não é erro nem campo vazio sem texto", "permissão de rede local negada tem estado próprio", "tráfego mostra a interface medida". |
| 17 | §15 riscos | Tabela atual | Novas linhas: mascaramento de MAC (alto), offsets do `ifmibdata` sem doc (médio), permissão de rede local sem teste (alto), `RTM_GET` com resultado velho por 1200 s (médio). |

## 7. Decisões que dependem do dono

Só produto, legal e privacidade. Em português comum, com a consequência de cada resposta.

1. **Onde distribuir o app?**
   - *Fora da loja (GitHub, com assinatura e notarização):* o app mede latência sem restrição e pode oferecer MAC opcional. Exige uma conta paga de desenvolvedor Apple (o custo não foi pesquisado).
   - *Só build local:* sem custo, mas só quem sabe compilar instala.
   - *Mac App Store:* adiada. Se escolhida, a latência fica no RTT TCP e o `arp` some.
2. **Aceita um modo opcional que mostra o MAC do aparelho (usando o `arp` do sistema)?**
   - *Sim, desligado por padrão:* ganha identidade melhor para quem liga. O app passa a guardar um identificador de pessoas, então a retenção de 30 dias do PRD precisa cobrir isso e a UI avisa.
   - *Não:* o app é mais simples e mais privado, mas aparelhos sem Bonjour ficam só com IP.
3. **Lista de fabricantes (IEEE): baixar no momento do uso, embutir ou não usar?** A licença de redistribuição não está clara (A2 §5). *Baixar* evita o risco, mas faz o app acessar a internet por conta própria, o que toca a regra de "nenhum dado externo". *Embutir* exige confirmar os termos. *Não usar* é o mais seguro, e só importa se o MAC existir.
4. **Qual versão mínima do macOS prometer?** Hoje só a 27.2 foi testada. *Prometer a 14* exige testar nela e no Mac Intel. *Prometer só a atual* é honesto, mas reduz o público.
5. **Rede com Wi-Fi e Ethernet ao mesmo tempo: o que o usuário vê?** *Só a interface primária:* mais simples, mas o tráfego da outra interface some. *Todas as ativas, separadas:* mais fiel, mais telas. O PRD não decide.
6. **Adapter de roteador: aceita que ele peça a senha de administração do roteador?** *Sim:* guardada só no Keychain, com risco se o usuário reaproveita senha. *Não:* sem consumo por aparelho. Antes disso, o dono precisa autorizar o teste no roteador (PRD §10).
7. **O nome "OpenWifi" está livre?** Não pesquisei marcas. Vale checar antes de publicar (PRD §16 já pede verificar disponibilidade do repositório).

## 8. Próximos passos do esqueleto

Cada passo é pequeno, em ordem, com um teste de aceite. Todos respeitam "medido, inferido, indisponível".

1. **Domínio: identidade e fontes.** Acrescentar `identityLevel` e `interfaceName` a `NetworkDevice`, e `DataSource` com a origem do nome. *Aceite:* testes unitários mostrando que IP sozinho nunca vira identidade forte; `macAddress` ausente é um valor válido.
2. **Presença com evidência ativa.** `PresenceTracker` só confirma com resposta ICMP ou Bonjour; `RTM_GET` vira pista. *Aceite:* teste em que um host só "resolvido" não fica `active` indefinidamente.
3. **Guarda de intervalo no `TrafficRateCalculator`.** Descartar amostra de 32 bits após intervalo maior que um limite. *Aceite:* teste com dois wraps em um intervalo longo devolvendo `nil`, não um valor plausível.
4. **`InterfaceTrafficSampler` real.** `IFMIB_IFDATA` com validação cruzada contra `getifaddrs` (A, IFMIB, B, com wrap) e fallback de 32 bits. *Aceite:* buffer de fixtures cobrindo offset certo e errado; teste manual comparando com `netstat -ib` dentro da tolerância de uma janela de 2 s.
5. **`NetworkPathObserver` real.** SCDynamicStore para gateway e interface primária; `NWPathMonitor` só como gatilho. *Aceite:* testes com provedor falso; checagem manual no Mac de teste: gateway `192.168.0.1` na interface `en0`.
6. **`LatencyProbe` real.** ICMP DGRAM com id e seq, classificação em resposta, "sem rota" (`EHOSTUNREACH` e `ENETUNREACH`) e perda; fallback TCP rotulado. *Aceite:* testes com socket falso; manual contra `ping` na mesma ordem de grandeza, e blackhole `192.0.2.1` dando perda.
7. **`.app` assinado de verificação (duas variantes: com e sem sandbox).** Repetir ICMP, `RTM_GET`, `DNSService*` e UDP de varredura. *Aceite:* tabela de resultados por variante, preenchendo as lacunas de A2 no sandbox.
8. **Estado de permissão de Rede Local.** Nova porta e estado de UI "permissão negada". *Aceite:* sessão manual com o dono concedendo, negando e reconcedendo; relatório do que mudou, incluindo o MAC.
9. **`DeviceDiscovery` real.** Varredura por interface (lotes de 32), `RTM_GET`, `DNSServiceBrowse` mais `NWBrowser`, mDNS PTR. *Aceite:* na rede de teste, os IPs batem com `arp -an`; a lista de tipos Bonjour fica no `Info.plist`.
10. **Persistência.** SQLite com migrações para presença e latência de 24 h, retenção e "apagar histórico". *Aceite:* testes de migração e de retenção; nenhum MAC gravado a menos que o modo opcional esteja ligado.
11. **Preferências, `SMAppService` e notificações opt-in.** *Aceite:* ativar e desativar o início no login; notificações com debounce.
12. **`ArpMacReader` opcional**, só se o dono responder sim à decisão 2. *Aceite:* build sem sandbox mostra o MAC; build com sandbox não compila o módulo.
13. **Spike do roteador (M3).** Só com autorização. *Aceite:* relatório que responde aos 6 passos de PRD §10 e decide entre suportado, experimental e não implementável.

## 9. Lacunas desta revisão

- Não executei nada novo; só li o PRD, os relatórios e o esqueleto.
- O esqueleto foi apenas folheado: confirmei portas, lógica, mocks e UI, mas não reli os testes. O número 28 vem da tarefa.
- Nenhuma fonte oficial adicional foi aberta; tudo o que depende da Apple (notarização, entitlements, Local Network) está marcado como não verificado.
