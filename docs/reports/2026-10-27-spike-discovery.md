# Spike A2: descoberta de dispositivos (OpenWifi)

Data: 2026-10-27. Máquina: macOS 27.2 (Darwin 27.2.0), Xcode 27.0, Swift 6.4, arm64, uid 501 (sem root).
Rede: uma /24 doméstica (`192.168.0.0/24`, gateway `.1`). O Mac está em DUAS interfaces na mesma sub-rede: `en0` = Ethernet, `en1` = Wi-Fi.
Tudo abaixo foi executado de verdade; scripts descartáveis ficam fora do repo (scratchpad). MACs e hostnames reais foram omitidos; IPs mascarados (`.x`) exceto o gateway (`.1`).

## Resumo dos veredictos

| # | Item | Veredito |
|---|---|---|
| 1 | Ler tabela ARP/NDP via sysctl sem shell, sem root | FAILS para IPv4 (nenhuma entrada), WORKS-WITH-CAVEAT para IPv6 (entradas vêm, MAC mascarado) |
| 1b | Alternativa: `RTM_GET` por host via socket `PF_ROUTE` | WORKS-WITH-CAVEAT (confirma host resolvido, MAC vem mascarado `02:00:00:00:00:00`) |
| 2 | Varredura limitada da /24 para popular o cache | WORKS (254 envios em ~190 ms, 6 hosts resolvidos, bate com `arp -an`) |
| 3 | Bonjour/mDNS (NWBrowser e DNSServiceBrowse) a partir de binário CLI | WORKS-WITH-CAVEAT (CLI sim; `_services._dns-sd._udp` falha no NWBrowser, funciona via `dnssd`) |
| 4 | DNS reverso | FAILS para `getnameinfo` (0/7), WORKS-WITH-CAVEAT para mDNS PTR (2/7) |
| 5 | OUI offline (IEEE) | WORKS-WITH-CAVEAT (fonte existe, mas o MAC real não está acessível ao app; licença sem texto explícito) |
| 6 | Identidade entre mudanças de IP | WORKS-WITH-CAVEAT (sem MAC; só Bonjour TXT/identificadores, cobertura baixa) |
| 7 | Fingerprint passivo do roteador (SSDP/UPnP) | FAILS neste roteador (zero respostas SSDP, nenhuma porta de descrição aberta) |

Achado que muda o PRD: no macOS 27.2 um processo que não é binário da plataforma Apple NÃO recebe MAC de ninguém na rede (IPv4 nem IPv6). Impacta itens 1, 5 e 6.

## 1. Tabela de vizinhos via sysctl (sem shell)

Evidência (rodado como uid 501):

- IPv6, `sysctl {CTL_NET, PF_ROUTE, 0, AF_INET6, NET_RT_FLAGS, RTF_LLINFO}`: funciona sem root. 23 entradas em 0,1 ms; com `NET_RT_DUMP2` 40 entradas (`ndp -an`: 42 linhas de dados). Dentre as entradas, todas as com endereço de link-layer vêm com `sdl_alen=6` e valor `02:00:00:00:00:00` (14 de 14), as demais são `incomplete`.
- IPv4, o mesmo mib (`AF_INET`): `len=0` (zero bytes) nas 3 execuções, mesmo com 7+ vizinhos presentes e `arp -an` listando 23 linhas. `NET_RT_FLAGS_PRIV` (10) e `NET_RT_DUMPX` também não trazem vizinhos. `NET_RT_DUMP`/`DUMP2` devolvem 16 mensagens, todas rotas de interface (flags `0x901`, `sdl_alen=0`), não as entradas LLINFO que `netstat -rn` mostra (`UHLWIir`).
- Por que `arp -an` funciona e o código próprio não: teste com binário de plataforma. O `/usr/bin/python3` (Platform identifier 27) recebe 3440 bytes do mesmo mib IPv4; o Python do Homebrew (ad-hoc) recebe 0; binário Swift ad-hoc recebe 0; binário assinado com Apple Development recebe 0; `.app` assinado com Apple Development + hardened runtime + `NSLocalNetworkUsageDescription`/`NSBonjourServices` recebe 0 (testado, ver 1b). `/usr/sbin/arp` não tem entitlements (`codesign -d --entitlements -` vazio), então o gate é "binário de plataforma", não entitlement.
- Local Network privacy NÃO é o gate: TN3179 diz que ferramentas de linha de comando executadas do Terminal têm acesso à rede local liberado automaticamente, e mesmo assim receberam 0 bytes / MAC mascarado.
- Isso é comportamento observado, não encontrei documentação Apple sobre ele. Padrão idêntico ao MAC mascarado do iOS 11+.

Snippet (parse correto do `rt_msghdr` + `sockaddr_dl`; hoje só devolve algo útil para IPv6, e com MAC mascarado):

```swift
var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET6, 2 /*NET_RT_FLAGS*/, 0x400 /*RTF_LLINFO*/]
var len = 0
sysctl(&mib, 6, nil, &len, nil, 0)            // IPv4: len == 0 on macOS 27.2 for non-platform binaries
var buf = [UInt8](repeating: 0, count: len)
sysctl(&mib, 6, &buf, &len, nil, 0)
// walk: rt_msghdr (92 bytes), then sockaddrs by rtm_addrs bit order (RTAX_DST, RTAX_GATEWAY...),
// each rounded to 4 bytes; gateway is sockaddr_dl: nlen=buf[p+5], alen=buf[p+6], mac at p+8+nlen
```

Comparação com ferramentas de shell: `arp -an` (platform) lista os MACs reais e funciona sem root; `ndp -an` idem. São a única via que entrega MAC real, mas é shell-out (conflita com "sem runtime externo", e com App Sandbox).

Recomendação OpenWifi: não depender da leitura sysctl da tabela IPv4. Usar `RTM_GET` por IP (1b) como "ARP confirmou o host" e tratar MAC como dado opcional/ausente. Se o MAC for requisito de produto, a única via testada é executar `/usr/sbin/arp -an` (binário de sistema, sem root) fora do App Sandbox; decidir explicitamente, não por padrão.
Riscos: o comportamento pode mudar entre betas do macOS 27; qualquer feature que dependa de MAC (OUI, identidade por MAC, `MAC randomizado`) fica inviável no caminho nativo.

## 1b. RTM_GET por host (socket PF_ROUTE, sem root)

Evidência: `route -n get` equivalente em Swift devolve, para o IP resolvido, `RTM_GET` com `flags=0x15020445` (`UP,HOST,DONE,LLINFO,WASCLONED,IFSCOPE,IFREF,ROUTER` para o gateway), `sdl_alen=6` e dados `02:00:00:00:00:00` (leitura crua dos bytes do `sockaddr_dl`). Os 254 IPs da /24 consultam em 9-24 ms no total. Host sem entrada resolvida devolve `ESRCH`/`alen=0`. O resultado coincide, por IP, com as entradas completas de `arp -an` (ver item 2).

```swift
let s = socket(PF_ROUTE, SOCK_RAW, AF_INET)
// rt_msghdr{ rtm_type=RTM_GET, rtm_flags=RTF_UP|RTF_HOST|(RTF_IFSCOPE if scoped), rtm_addrs=RTA_DST, rtm_index=ifIndex }
// followed by sockaddr_in(dst). write(s,...); read replies until rtm_pid==getpid() && rtm_seq==seq
// parse addrs in RTAX order; RTAX_GATEWAY is AF_LINK: alen==6 -> resolved (mac is 02:00:00:00:00:00)
```

Recomendação: usar `rtm_index`/`RTF_IFSCOPE` por interface (Mac multi-homed, ver item 2).

## 2. Varredura limitada da /24

Procedimento: um datagrama por IP (`.1` a `.254`), em lotes de 32 com 20 ms entre lotes (concorrência efetiva <= 32, envio não bloqueante), socket preso à interface com `IP_BOUND_IF` (valor 25), depois `RTM_GET` dos 254 IPs. Mesma varredura repetida várias vezes.

| Sondagem | Envio (254 pacotes) | Espera | Total | Hosts resolvidos | Respostas |
|---|---|---|---|---|---|
| UDP `sendto` porta fechada 33434 (1 byte) | ~190 ms | 300 ms | ~500 ms | 6 | n/a |
| UDP | ~190 ms | 1500 ms | ~1,7 s | 6 | n/a |
| ICMP echo via `SOCK_DGRAM`/`IPPROTO_ICMP` (sem root) | ~190 ms | 1500 ms | ~1,7 s | 6 | 6 echo replies |
| ICMP, concorrência 8 | ~750 ms | 1000 ms | ~1,8 s | 6 | 5 |

- 6 hosts resolvidos em `en0` = gateway (`.1`), o próprio Mac (`.185`) e 4 outros (`.102`, `.128`, `.209`, `.238`). `arp -an` logo depois lista os mesmos 6 mais `.255` (broadcast): coincidência exata dos IPs. Todos os 6 resolvidos respondem ao ICMP (6/6); nenhuma diferença ARP vs ICMP nesta rede.
- Pela Wi-Fi (`en1`, escopo próprio): 8 resolvidos, incluindo `.124` que não aparece em `en0` e o IP do próprio Wi-Fi do Mac (`.204`). Conclusão: o Mac está em duas interfaces na mesma /24; varrer e ler por interface (`IP_BOUND_IF` + escopo no `RTM_GET`), senão o tráfego sai por uma interface qualquer (uma execução sem bind mostrou 246 `EHOSTUNREACH` (65) e `EHOSTDOWN` (64) no envio).
- Erros de envio `EHOSTDOWN`/`EHOSTUNREACH` são sinal negativo útil: o kernel já marcou o vizinho como inalcançável.
- `UDP` basta para popular o cache (500 ms totais); ICMP agrega confirmação de que responde ping. Ambos sem root. 300 ms de espera foram suficientes aqui.
- Cobertura: 4 outros dispositivos de uma casa maior; não há lista do roteador para comparar. Não simulei isolamento nem aparelhos desligados.

Comportamento documentado (não simulado):
- Wi-Fi com client isolation / AP isolation: ARP e mDNS entre clientes não passam; só o gateway e o próprio Mac aparecem. OpenWifi deve mostrar "descoberta limitada" (PRD seção 3: "redes isoladas podem ocultar hosts").
- Aparelhos em sono profundo (iOS, IoT) ignoram ARP ou respondem só via Sleep Proxy/Bonjour; "sem resposta" não é "desconectado" (PRD seção 3 já proíbe essa afirmação).
- Entrada ARP expira em 1200 s (`net.link.ether.inet.max_age`): confirma o corte `stale` após 3 varreduras de 60-120 s do PRD seção 9.

Snippet (UDP, mínimo):

```swift
let s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
var ifx = if_nametoindex("en0"); setsockopt(s, IPPROTO_IP, 25 /*IP_BOUND_IF*/, &ifx, 4)
fcntl(s, F_SETFL, fcntl(s, F_GETFL) | O_NONBLOCK)
for batch in stride(from: 1, to: 255, by: 32) {
  for h in batch..<min(batch + 32, 255) { /* sendto 1 byte to prefix.h:33434 */ }
  usleep(20_000)
}
usleep(300_000)   // then RTM_GET each IP (1b)
```

ICMP sem root: `socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)` com echo request (type 8, checksum calculado pelo app, id/seq no payload) e `recvfrom` não bloqueante; funcionou sem root.

Recomendação: varredura incremental por interface ativa, UDP + ICMP, lotes <= 32, `RTM_GET` ao final. Risco: a rede pode ter 2 interfaces ativas na mesma sub-rede (caso comum com dock + Wi-Fi), tratar como redes separadas na UI.

## 3. Bonjour/mDNS

- `NWBrowser(for: .bonjour(type:domain:))` funciona em binário CLI: estados `ready` para todos os tipos testados (`_airplay`, `_companion-link`, `_device-info`, `_homekit`, `_googlecast`, `_ipp`, `_smb`, `_raop`, `_expo`, `_apple-mobdev2`, `_remotepairing`, `_philipstv_rpc`). Primeiros resultados em 10-190 ms (cache do mDNSResponder). Instâncias achadas: `_airplay` 1, `_companion-link` 1, `_smb` 1, `_raop` 1, `_expo` 2, `_apple-mobdev2` 1, `_remotepairing` 7, `_philipstv_rpc` 1; `_device-info`, `_homekit`, `_googlecast`, `_ipp` 0 nesta rede. Vários desses são serviços do próprio Mac.
- `NWBrowser` com `_services._dns-sd._udp` falha: `failed(-65540: BadParam)`. Enumeração de tipos precisa de `DNSServiceBrowse` (`import dnssd`, biblioteca do sistema, sem shell): achou 9 tipos em 4,1 s (`_airplay._tcp _apple-mobdev2._tcp _asquic._udp _companion-link._tcp _expo._tcp _philipstv_rpc._tcp _raop._tcp _remotepairing._tcp _smb._tcp`), mesmo conjunto do `dns-sd -B`.
- `.bonjourWithTXTRecord` devolve chaves TXT (ex.: `_airplay`: `model`, `deviceid`, `features`; `_companion-link`: `rpBA`, `rpMac`, `rpHN`; `_remotepairing`/`_apple-mobdev2`: `identifier`), sem custo extra.
- Mapear serviço para IP: duas vias testadas. (a) `NWConnection` ao endpoint `.service` e ler `currentPath?.remoteEndpoint`: funciona mas conecta ao serviço do aparelho (intrusivo) e `_philipstv_rpc` não resolveu; vários `_remotepairing` resolveram só IPv6 link-local. (b) `DNSServiceResolve` + `DNSServiceGetAddrInfo` (IPv4): sem conexão ao dispositivo; resolveu 6 hosts (2 `_expo`, `_airplay`, `_smb`, `_raop`, `_apple-mobdev2`; `_philipstv_rpc` não resolveu), dos quais o `_apple-mobdev2` caiu em IP que o `RTM_GET` também confirma como resolvido, 3 eram o próprio Mac, `_smb`/`_raop` apontam para um IP /24 que não estava no conjunto resolvido do `en0` naquele momento (pode estar só na outra interface). Mapear para ARP é possível por IP; por MAC não (MAC mascarado).
- Local Network privacy (TN3179, https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy): disponível desde macOS 15; macOS libera automaticamente daemons, programas root e "command-line tools run from Terminal or over SSH, including any child processes", por isso o binário CLI sem assinatura funcionou sem prompt. Um `.app` (menu bar) é sujeito ao prompt: exige `NSLocalNetworkUsageDescription` e, para browse Bonjour, `NSBonjourServices` com cada tipo (`_airplay._tcp` etc.). Um `.app` assinado só com esses plist keys, sem fazer operação de rede local, não dispara prompt; NÃO testei o prompt/negação em `.app` (exigiria ação do dono). Sem permissão, o browse falha com política negada em vez de mostrar vazio.

```swift
// enumerate service types (no shell)
DNSServiceBrowse(&ref, 0, 0, "_services._dns-sd._udp", "local.", cb, ctx)   // pump via DNSServiceRefSockFD + poll

// browse a known type with TXT
let b = NWBrowser(for: .bonjourWithTXTRecord(type: "_airplay._tcp", domain: nil), using: .tcp)
b.browseResultsChangedHandler = { results, _ in /* .service(name,type,domain,_), metadata .bonjour(txt) */ }
b.start(queue: .main)

// service -> IPv4 without connecting
DNSServiceResolve(&r, 0, ifIndex, name, "_smb._tcp", "local.", resolveCb, ctx)    // -> host target
DNSServiceGetAddrInfo(&g, 0, 0, UInt32(kDNSServiceProtocol_IPv4), host, addrCb, ctx)
```

Recomendação: `DNSServiceBrowse` para enumerar tipos + `NWBrowser(.bonjourWithTXTRecord)` por tipo, `DNSServiceResolve`/`GetAddrInfo` para IP. Listar em `NSBonjourServices` só os tipos usados (alguns ~10-15) e documentar no `Info.plist`. Risco: tipos desconhecidos (ex.: `_expo`, `_philipstv_rpc`) só aparecem via enumeração, que exige o plist declarar o tipo; usar a lista fixa e tratar permissão negada.

## 4. DNS reverso

Hosts testados: 7 IPs da /24 (resolvidos + um da Wi-Fi), 1,5 s por IP para mDNS.

- `getnameinfo(..., NI_NAMEREQD)` (resolver do sistema, 18-20 ms por consulta): 0 de 7 (`EAI_NONAME`). O roteador não publica PTR para clientes.
- mDNS PTR `<ip>.in-addr.arpa` via `DNSServiceQueryRecord` com `kDNSServiceFlagsForceMulticast`: 2 de 7 (um deles o próprio Mac). Só aparelhos que respondem ao próprio PTR multicast (macOS/iOS e alguns IoT) aparecem.
- Taxa útil combinada: 2/7 (~29%). Fora de escopo: NetBIOS e `dscacheutil`.

```swift
DNSServiceQueryRecord(&ref, UInt32(kDNSServiceFlagsForceMulticast), 0,
  "\(reversedOctets).in-addr.arpa.", UInt16(kDNSServiceType_PTR), UInt16(kDNSServiceClass_IN), cb, ctx)
```

Recomendação: tentar mDNS PTR (timeout 1-1,5 s, concorrência baixa) e, para o restante, nome vindo do Bonjour; `getnameinfo` só como tentativa barata, não confiar. Nome não é identidade.

## 5. Vendor por OUI

- Fonte: IEEE `https://standards-oui.ieee.org/oui/oui.csv` (MA-L), baixada em 2026-10-27: 3.866.517 bytes, 40.421 linhas, 20.152 organizações distintas, ~1,17 MB gzip; `oui28/mam.csv` (MA-M, 761 KB) e `oui36/oui36.csv` (MA-S, 674 KB) idem. O download exigiu `User-Agent` padrão do curl (UA de navegador recebeu HTTP 418). 107 linhas `Private` (assinaturas privadas, sem nome).
- Licença: o IEEE publica a lista como listagem pública; não achei texto de licença/redistribuição no FAQ da Registration Authority. Para um app MIT, o caminho mais seguro é baixar sob demanda do IEEE ao atualizar (e não vendorar a lista no repositório) ou confirmar os termos com o IEEE. Pendência a decidir, não afirmei que é livre.
- Impacto do achado do item 1: o app não recebe o MAC real de outros dispositivos, então o lookup por OUI não funciona no caminho nativo. Sobre bit localmente administrado (`0x02` no primeiro octeto): os 6 hosts mostraram `02:00:00:00:00:00` (mascarado), ou seja 6/6 com o bit LA setado por causa da máscara, não por MAC aleatório real. Contagem real de MACs privados/aleatórios fica indisponível; via `arp -an` (shell) seria possível. Com Wi-Fi privado do iOS/Android/Windows, boa parte dos aparelhos teria o bit LA: vendor via OUI não vale para eles de qualquer forma.

Recomendação: não incluir OUI no MVP (sem MAC não há entrada). Se virar enriquecimento opcional via `arp -an`, usar índice binário prefixo de 3 bytes → string (~1 MB), e não rotular vendor quando `byte0 & 0x02 != 0`.

## 6. Identidade entre trocas de IP

- Evidência disponível ao app: IP, nome de instância Bonjour e chaves TXT. Sem MAC (mascarado).
- Identificadores estáveis observados via TXT (valores não registrados aqui): `_airplay` `deviceid` (17 chars, 5 `:`, formato de MAC), `_companion-link` `rpBA` (17 chars, 5 `:`, formato de MAC/BT), `_apple-mobdev2` e `_remotepairing` `identifier` (36 chars, formato UUID). Ou seja, alguns aparelhos Apple publicam um identificador estável no próprio anúncio mDNS; AirPlay `deviceid` costuma ser o MAC de Wi-Fi (isso é convenção do protocolo, não verifiquei contra o MAC real, e não é garantido sob Wi-Fi privado).
- Correlação possível: chave composta `(instance name, TXT id)` quando existir; quando não existir, nome Bonjour + hostname mDNS (`.local`) como evidência fraca. Aparelhos sem Bonjour (maioria de IoT, TVs em standby) só têm IP, sem como seguir na troca de IP.
- Instância Bonjour com sufixo ` (2)` indica colisão de nome, não troca de aparelho.

Recomendação: modelo de identidade em níveis (forte: UUID/`deviceid` do TXT; médio: nome da instância estável por N varreduras; fraco: IP) e UI que mostre "provável o mesmo aparelho" quando só nome bate. Risco: falsos positivos entre aparelhos com mesmo nome, e perda de histórico para aparelhos sem Bonjour.

## 7. Fingerprint passivo do roteador (TP-Link, gateway `.1`)

- SSDP: 1 `M-SEARCH` (`upnp:rootdevice`, `MX: 2`) multicast em `239.255.255.250:1900` preso a `en0`, 3 s: 0 respostas. Repetido em `en1`: 0. M-SEARCH unicast direto ao gateway: 0. Teste cruzado com `ssdp:all` no `/usr/bin/python3` (binário de plataforma): 0 respostas de qualquer aparelho. Logo o roteador não responde SSDP nesta configuração (UPnP desligado ou sem IGD ativo); nenhum outro aparelho respondeu também.
- Descrição do dispositivo: como não veio `LOCATION`, tentei apenas 2 URLs padrão de descrição UPnP (`:5000/rootDesc.xml`, `:49152/gatedesc.xml`): conexão recusada nas duas. Não toquei em `/cgi-bin`, login, credenciais ou páginas de admin.
- Campos esperados quando UPnP IGD está ativo (documentação UPnP, não observado aqui): `deviceType`, `friendlyName`, `manufacturer`, `modelName`, `modelNumber`, às vezes `serialNumber`/`UDN`; firmware normalmente NÃO aparece nesses campos (às vezes no cabeçalho `SERVER:`).
- Contadores: o serviço `WANCommonInterfaceConfig` do IGD define `GetTotalBytesReceived`/`GetTotalBytesSent` (e variantes de pacotes), totais do link WAN do roteador, sem dado por cliente. Não executei nenhuma ação SOAP (somente leitura de descrição era o escopo); não confirmei neste roteador.
- Conclusão: não há fingerprint local passivo disponível neste TP-Link (EX520/AX53) com UPnP inativo. O usuário pode ativar UPnP no roteador, mas isso é ação dele.

Snippet (descoberta SSDP, passiva):

```swift
let msg = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: upnp:rootdevice\r\n\r\n"
// UDP socket, IP_BOUND_IF to the active interface, sendto 239.255.255.250:1900, recvfrom for 3 s,
// read LOCATION header, GET that one URL only (device description XML).
```

Recomendação: tratar SSDP/UPnP como adapter opcional ("se o roteador responder"), nunca como requisito; totais WAN apenas rotulados "do roteador", não por cliente. Dados por cliente continuam exigindo adapter de roteador com credencial (fora do escopo deste spike).

## Decisões e riscos para o OpenWifi

1. Presença: varredura UDP+ICMP por interface + `RTM_GET` por IP funciona sem root e é rápida (~0,5-1,7 s para a /24 inteira). Use isso como "host visto".
2. MAC: indisponível para app não-Apple no macOS 27.2 (testado em CLI ad-hoc, CLI assinado e `.app` assinado com hardened runtime). Reescrever pontos do PRD que assumem MAC (identidade, vendor, MAC randomizado) ou aceitar `arp -an` como shell-out opcional (incompatível com App Sandbox; decisão do dono).
3. Nome: Bonjour é a melhor fonte (TXT traz modelo e ids); DNS reverso cobre pouco (2/7).
4. Roteador: sem SSDP/UPnP aqui; fingerprint não vem de graça.
5. A ser verificado antes do MVP: efeito da permissão Local Network sobre a máscara de MAC em `.app` (requer o dono conceder e reler), e se a máscara muda em outras versões do macOS 27.

## Reproduzir

Scripts: `/private/tmp/claude-501/-Volumes-BarbaExt-Projects-OpenSources-OpenWifi/713a2400-8d21-4d5e-a422-cbfd2447461b/scratchpad/spike-discovery/` (`Neighbors.swift`, `RtmGet.swift`, `sweepdir/`, `bonjourdir/`, `dnssddir/`, `ssdpdir/`, `appdir/`). Não fazem parte do repositório.
