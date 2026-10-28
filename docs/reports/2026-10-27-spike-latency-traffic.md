# Spike A1: latência e tráfego de interface (2026-10-27)

Ambiente: macOS 27.2 (Darwin 27.2.0), Xcode 27.0, Swift 6.4, arm64, usuário não-root (uid 501). Rede: en0 (Ethernet, 192.168.0.x) e en1 (192.168.0.y) na mesma LAN, gateway 192.168.0.1. Tudo abaixo foi executado de verdade; scripts descartáveis ficaram no scratchpad (fora do repo).

## Resumo dos veredictos

| # | Item | Veredito |
|---|---|---|
| 1 | Gateway + interface sem shell | WORKS |
| 2 | ICMP echo sem root (DGRAM) | WORKS-WITH-CAVEAT (sandbox exige `network.server`) |
| 3 | RTT TCP via NWConnection | WORKS-WITH-CAVEAT |
| 4 | Contadores 64-bit sem root | WORKS-WITH-CAVEAT (NET_RT_IFLIST2 e getifaddrs vêm truncados em 32 bits; usar IFMIB_IFDATA) |
| 5 | NWPathMonitor | WORKS-WITH-CAVEAT (doc oficial; não simulado) |
| 6 | App Sandbox | WORKS-WITH-CAVEAT (ICMP só com `network.client` + `network.server`; medido, doc Apple não cobre) |

---

## 1. Gateway e interface ativa: WORKS

Duas rotas sem shell, ambas sem root.

Evidência (`gw`):
```
== sysctl NET_RT_FLAGS ==
default via 192.168.0.1 dev en0 flags=0x40010803 scoped=false
default via 192.168.0.1 dev en1 flags=0x41010803 scoped=true
== SCDynamicStore State:/Network/Global/IPv4 ==
Router=192.168.0.1 PrimaryInterface=en0 PrimaryService=26D7F19C-...
```
Referência: `route -n get default` -> gateway 192.168.0.1, interface en0; `netstat -rn -f inet` -> `default 192.168.0.1 UGScg en0` e `default 192.168.0.1 UGScIg en1` (`I` = IFSCOPE). Resultado idêntico.

Recomendação: usar `SCDynamicStore` (`State:/Network/Global/IPv4` -> `Router`, `PrimaryInterface`) como fonte primária (3 linhas, sem parsing binário) e registrar `SCDynamicStoreSetNotificationKeys` nessa chave para reagir a troca de rede/gateway. O sysctl `NET_RT_FLAGS` fica como fallback e revela as rotas escopadas (`RTF_IFSCOPE`, uma por interface), úteis para probar uma interface específica.

```swift
import SystemConfiguration
func primaryRoute() -> (gateway: String, interface: String)? {
  guard let s = SCDynamicStoreCreate(nil, "openwifi" as CFString, nil, nil),
        let d = SCDynamicStoreCopyValue(s, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
        let r = d["Router"] as? String, let i = d["PrimaryInterface"] as? String else { return nil }
  return (r, i)
}
```
Riscos: sem rota IPv4 a chave some (retornar nil = "sem rede"); IPv6-only não coberto (chave `Global/IPv6`); funciona dentro do App Sandbox (medido, item 6).

## 2. ICMP echo sem privilégio: WORKS-WITH-CAVEAT

`socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)` abre como uid 501 sem erro.

Evidência (10 echos, 56 B de payload, timeout 1 s) vs `ping -c 10 -i 0.2`:
```
192.168.0.1: sent=10 recv=10 lost=0 min/avg/max=1.42/1.72/2.20 ms     (ping: 1.445/1.944/2.472)
1.1.1.1:     sent=10 recv=10 lost=0 min/avg/max=11.91/13.20/13.98 ms  (ping: 11.704/15.386/21.944)
```
Mesma ordem de grandeza (diferença é variação de jitter entre rodadas, não de método).

Comportamento do kernel (testado com pacotes forjados, 1.1.1.1):
- Checksum: o kernel recalcula. Checksum errado (`0xDEAD`) e zero foram aceitos e o eco voltou válido. Não é obrigatório calcular, mas é barato e correto calcular.
- ID: NÃO é reescrito (diferente do Linux). Enviado `0xBEEF`, voltou `0xBEEF`; `id=0` voltou `0`.
- Sem demultiplexação por ID: duas sockets DGRAM ICMP abertas receberam ambas o mesmo eco (`two-sockets sock1 got reply: true / sock2 got reply: true`). Logo, filtrar sempre por ID + seq; usar ID aleatório por instância/socket.
- Resposta traz o header IP (`recv n=84 ihl=20 ttl=58 type=0`): 20 B IP + 8 B ICMP + 56 B. Pular `ihl` antes de ler o ICMP. TTL disponível (bônus: estimar hops).
- Respostas atrasadas de probe anterior chegam depois do timeout (`non-matching type=0 seq=0` visto com timeout de 2 ms); descartar por seq.
- Timeout/bloqueio: `192.0.2.1` (TEST-NET-1, blackhole) e `192.168.0.250` (host inexistente na LAN): `sendto` OK, nenhum pacote volta, `poll` expira -> `recv=0 lost=2`; não há erro ICMP nem errno. Indistinguível de host que filtra ICMP (confirma a ressalva do PRD: perda != indisponibilidade).
- Sem rota: não deu para desligar Wi-Fi (proibido), mas `IP_BOUND_IF` numa interface sem IPv4 reproduz o caminho: `awdl0`/`llw0` -> `sendto = -1 errno=65 (No route to host)` síncrono. Portanto "sem rota" aparece como erro de `sendto` (EHOSTUNREACH 65 / provável ENETUNREACH 51), não como timeout.
- `IP_BOUND_IF` funciona sem root: `en0` e `en1` ambos responderam ao 1.1.1.1 (permite medir cada interface separadamente).
- Host que "bloqueia ICMP": nenhum host real bloqueante encontrado (microsoft.com respondeu 15,8 ms); o blackhole 192.0.2.1 cobre o comportamento.

Recomendação: socket DGRAM ICMP, `poll()` com timeout (1 s), ID aleatório de 16 bits, seq crescente, validar `type==0`, id e seq. Rodar numa fila dedicada (não na main). Classificar: resposta -> RTT; `sendto` com EHOSTUNREACH/ENETUNREACH -> "sem rota"; só timeout -> "perda/filtrado" e, se o TCP fallback (item 3) responder, mostrar "ICMP filtrado, RTT TCP". Relógio: `CLOCK_MONOTONIC`.

```swift
import Foundation
func icmpRTT(host: String, id: UInt16, seq: UInt16, timeoutMs: Int32 = 1000) -> Double? {
  let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP); guard fd >= 0 else { return nil }
  defer { close(fd) }
  var dst = sockaddr_in(); dst.sin_len = 16; dst.sin_family = sa_family_t(AF_INET)
  inet_pton(AF_INET, host, &dst.sin_addr)
  var pkt: [UInt8] = [8, 0, 0, 0, UInt8(id >> 8), UInt8(id & 0xff), UInt8(seq >> 8), UInt8(seq & 0xff)]
    + [UInt8](repeating: 0x42, count: 56)   // kernel fixes checksum (verified)
  func now() -> Double { var t = timespec(); clock_gettime(CLOCK_MONOTONIC, &t); return Double(t.tv_sec) * 1000 + Double(t.tv_nsec) / 1e6 }
  let t0 = now(); let addr = dst
  let sent = withUnsafePointer(to: addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(fd, pkt, pkt.count, 0, $0, 16) } }
  guard sent >= 0 else { return nil }              // errno 65 = no route
  while true {
    let left = timeoutMs - Int32(now() - t0); if left <= 0 { return nil }
    var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
    guard poll(&p, 1, left) > 0 else { return nil }
    var rb = [UInt8](repeating: 0, count: 1500)
    guard recv(fd, &rb, rb.count, 0) > 0 else { return nil }
    let ihl = Int(rb[0] & 0x0f) * 4          // IP header is included
    let rid = UInt16(rb[ihl + 4]) << 8 | UInt16(rb[ihl + 5]), rseq = UInt16(rb[ihl + 6]) << 8 | UInt16(rb[ihl + 7])
    if rb[ihl] == 0 && rid == id && rseq == seq { return now() - t0 }   // id is NOT rewritten
  }
}
```
(`pkt` precisa ser `var` só se o checksum for calculado; aqui o kernel corrige.)

Riscos: ver item 6 (sandbox). Rate-limit de ICMP em alguns roteadores/hosts (amostrar a cada 5 s conforme PRD é seguro). ICMP é tratado com prioridade diferente de TCP por alguns roteadores (RTT ICMP pode ser maior que o de dados).

## 3. RTT TCP com NWConnection: WORKS-WITH-CAVEAT

Evidência (4 tentativas cada, tempo até `.ready` ou `.waiting`):
```
1.1.1.1:443      ready 16.80 | 18.40 | 17.73 | 18.32 ms
1.1.1.1:80       ready 11.91 | 12.67 | 14.38 | 14.52 ms
192.168.0.1:80   ready  1.72 |  2.25 |  1.50 |  1.52 ms          (porta aberta)
192.168.0.1:53/443/22  waiting(ECONNREFUSED 61) after 1.4-3.3 ms  (RST do gateway)
192.0.2.1:443    timeout (x4)
```
Referências: ICMP 1.1.1.1 = 11,9-14,0 ms (TCP:80 11,9-14,5 ms, igual); `curl` `time_connect` 14,4 ms. TCP:443 deu ~17-18 ms, maior que o ICMP.

Ressalvas de medição:
- Mede SYN -> SYN/ACK (um RTT), mas passa pelo caminho de TCP/NWConnection (resolução de path, fila do Network.framework, possível TLS não aplicado aqui por usar `.tcp`), então tem overhead de ~1-4 ms e mais variação que ICMP. Não é "ping"; rotular na UI como "RTT TCP".
- Um RST (porta fechada) também é resposta válida e rápida (1,4-3,3 ms): prova que o host está vivo e dá RTT, mas NWConnection reporta como `.waiting(POSIXErrorCode 61)`, não `.failed`. Tratar `.waiting` com ECONNREFUSED como amostra válida e cancelar a conexão logo (senão o framework reentenda).
- Anomalia vista: 3 de 4 tentativas à 192.168.0.1:22 reportaram `.waiting` após ~1075 ms (retry interno do framework), contra 1,8 ms na primeira. Usar só o primeiro estado terminal e cancelar.
- Firewalls que descartam SYN dão timeout, igual ao ICMP bloqueado.
- Para gateway: a porta aberta (80) variou por roteador; não há porta universal. Estratégia: tentar ICMP; se falhar, TCP em 443, 80, 53 da lista; o mesmo vale para o destino da internet (443 em 1.1.1.1).

```swift
import Network
func tcpRTT(host: String, port: UInt16, timeout: Double = 2) async -> Double? {
  let c = NWConnection(host: .init(host), port: .init(rawValue: port)!, using: .tcp)
  let t0 = ContinuousClock.now
  return await withCheckedContinuation { k in
    nonisolated(unsafe) var done = false
    let finish: @Sendable (Bool) -> Void = { ok in
      guard !done else { return }; done = true; c.cancel()
      let d = ContinuousClock.now - t0; k.resume(returning: ok ? Double(d.components.attoseconds) / 1e15 + Double(d.components.seconds) * 1000 : nil)
    }
    c.stateUpdateHandler = { s in
      switch s {
      case .ready: finish(true)
      case .waiting(let e): if case .posix(.ECONNREFUSED) = e { finish(true) } else { finish(false) }
      case .failed: finish(false)
      default: break }
    }
    c.start(queue: .global())
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(false) }
  }
}
```
(Snippet testado em versão equivalente; a versão acima usa `ContinuousClock` e não foi compilada literalmente. Em produção proteger `done` com lock/actor, pois o handler e o timer rodam em filas diferentes.)

## 4. Contadores de interface: WORKS-WITH-CAVEAT

Achado principal, contraria a hipótese do spike: neste macOS 27.2, `NET_RT_IFLIST2` (`if_msghdr2.ifm_data`, declarado `if_data64`) devolve o campo de 64 bits com o byte-count TRUNCADO em 32 bits (palavra alta = 0). Prova (en0, bytes recebidos):
```
netstat -ib      : 42727577919
IFMIB_IFDATA     : 42727558550   (>>32 = 9)   <- 64-bit real, bate com netstat
NET_RT_IFLIST2   :  4072852480   (>>32 = 0)   = 42727558550 mod 2^32 (wrapped)
getifaddrs 32bit :  4072852480                 (igual ao IFLIST2)
```
Contadores de pacotes não foram comparados (valores < 2^32). Fonte 64-bit sem root que funciona: `sysctl [CTL_NET, PF_LINK, NETLINK_GENERIC(0), IFMIB_IFDATA(2), ifindex, IFDATA_GENERAL(1)]` (struct `ifmibdata`, `if_data64` embutido). Offsets medidos (arm64): `ifibytes` em +116, `ifobytes` em +124 (validado: igual ao `netstat -ib` byte a byte; obytes +124 confere com tx 9002549255). Esses offsets são do layout atual e NÃO são API pública estável: validar na inicialização comparando com `getifaddrs` (low 32 bits devem casar) e cair para getifaddrs com tratamento de wrap se divergir.

Nota: o sysctl tem `ifm_data` correto no layout `pack(4)` (ibytes em +96 da mensagem), mas o conteúdo vem truncado; não é erro de parsing (a palavra alta lida é 0 e o valor baixo é exatamente `netstat mod 2^32`).

Delta de 2 s sem root durante download (`curl` ~25 MB/s, `ash-speed.hetzner.com/100MB.bin`):
```
delta 2.005s  IFMIB rx=20498112 B/s  tx=112742 B/s | IFLIST2 rx=20498284 | getifaddrs32 rx=20498284
```
Os três concordam no delta (wrapping subtraction `&-` no 32-bit). `netstat -ib` em janela separada de 2 s: ~23,8 MB/s (janelas não idênticas, mesma ordem). Teste anterior com 30 MB: delta 25,76 MB/s (IFLIST2) vs 25,70 MB/s (getifaddrs).

Rollover: 32-bit estoura a cada 4 GiB; a ~25 MB/s isso ocorre em ~170 s. Com delta de 2 s e subtração com wrap (`after &- before`, ex.: `1000 &- 4294900000 = 68296`) o resultado é correto para um único wrap; subtração Int64 ingênua dá `-4294899000`. Com IFMIB 64-bit não há wrap prático.

Detectar troca/reset de interface: (a) `if_nametoindex` / índice mudou ou a interface primária do SCDynamicStore mudou; (b) contador atual < anterior (reset por down/up da interface; com 64-bit isso é reset real, com 32-bit pode ser wrap, por isso preferir IFMIB); (c) descartar a amostra e reiniciar a base em vez de calcular delta. `ifi_lastchange` não foi verificado.

Recomendação: ler `IFMIB_IFDATA` para a interface primária a cada 1-2 s (um sysctl pequeno, 180 B), com fallback `getifaddrs` + wrapping sub; guardar `(ifindex, rx, tx, timestamp)` por amostra.

```swift
import Foundation
func ifaceBytes(_ name: String) -> (rx: UInt64, tx: UInt64)? {
  var mib: [Int32] = [CTL_NET, PF_LINK, 0, 2 /*IFMIB_IFDATA*/, Int32(if_nametoindex(name)), 1 /*IFDATA_GENERAL*/]
  var len = 0
  guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len >= 132 else { return nil }
  var buf = [UInt8](repeating: 0, count: len)
  guard sysctl(&mib, 6, &buf, &len, nil, 0) == 0 else { return nil }
  return buf.withUnsafeBytes { ($0.loadUnaligned(fromByteOffset: 116, as: UInt64.self),
                                $0.loadUnaligned(fromByteOffset: 124, as: UInt64.self)) }
}
```
Fallback 32-bit (wrap-safe delta):
```swift
func ifaceBytes32(_ name: String) -> (UInt32, UInt32)? {
  var head: UnsafeMutablePointer<ifaddrs>?; guard getifaddrs(&head) == 0 else { return nil }; defer { freeifaddrs(head) }
  var c = head
  while let p = c { defer { c = p.pointee.ifa_next }
    if String(cString: p.pointee.ifa_name) == name, p.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK),
       let d = p.pointee.ifa_data { let s = d.assumingMemoryBound(to: if_data.self).pointee; return (s.ifi_ibytes, s.ifi_obytes) } }
  return nil
}  // delta = UInt64(now &- prev)
```
Risco principal: offsets do `ifmibdata` não documentados; mitigar com a checagem de sanidade acima e testes em cada versão de macOS suportada.

## 5. NWPathMonitor: WORKS-WITH-CAVEAT (apenas documentação, nada simulado)

Fonte: https://developer.apple.com/documentation/network/nwpath (lida em 2026-10-27; macOS 10.14+).
- `NWPath` expõe `status` (satisfied/unsatisfied/requiresConnection), `availableInterfaces` (ordem de preferência), `usesInterfaceType(_:)` (wifi, wiredEthernet, cellular, loopback, other), `gateways: [NWEndpoint]` ("gateways configured on the interfaces available to a path"), `supportsIPv4/IPv6/DNS`, `isExpensive`, `isConstrained`, `unsatisfiedReason`, `linkQuality`.
- `NWPathMonitor` ("an observer that you use to monitor and react to network changes") entrega um novo `NWPath` quando o path muda. A doc lida não detalha QUAIS campos mudam o disparo (ex.: trocar só o gateway na mesma interface) nem a latência da notificação: não verificado, e não simulei troca de rede.
- Limitação conhecida da API: `NWPath` não dá byte counters nem o RSSI; `gateways` lista todos os gateways das interfaces disponíveis, sem indicar o primário (no teste, havia duas rotas default, en0 e en1).

Recomendação: usar `NWPathMonitor` só como gatilho barato ("o path mudou, reavalie") e resolver gateway primário/interface via SCDynamicStore (item 1) no handler; assim a lógica não depende de semântica não documentada. Validar em campo troca Wi-Fi<->Ethernet e sleep/wake.

## 6. App Sandbox: WORKS-WITH-CAVEAT (medido; doc Apple insuficiente)

Documentação: a página oficial do entitlement (https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client) diz apenas "may open outgoing network connections". Não cita sockets ICMP nem sysctl: sobre esses pontos a doc é "unverified". O thread de fórum 775253 (DF bit em ICMP em app sandboxed; página bloqueada por verificação, só o resumo da busca foi lido) indica restrições em ICMP no sandbox, sem confirmar o comportamento.

Medido (empírico, ad-hoc signed `.app` com `com.apple.security.app-sandbox` + `network.client`; binário CLI solto com sandbox aborta com exit 133, precisa estar num bundle com `CFBundleIdentifier`):

| Chamada | `network.client` | `client` + `network.server` |
|---|---|---|
| SCDynamicStore (`Router`, `PrimaryInterface`) | WORKS | n/d |
| sysctl `NET_RT_FLAGS` | WORKS | n/d |
| sysctl IFMIB / IFLIST2 / getifaddrs | WORKS (IFMIB 64-bit confirmado) | n/d |
| NWConnection TCP (1.1.1.1:443 ~17-22 ms; gw:80 ~1,4-1,5 ms) | WORKS | n/d |
| ICMP DGRAM: `socket()` e `sendto()` | OK | OK |
| ICMP DGRAM: `recv()` da resposta | FAILS: `errno=1 Operation not permitted` (3/3 e 2/2 probes) | WORKS: 3/3, `1.1.1.1 12.90/13.70/14.28 ms` |

Conclusão: dentro do sandbox, ICMP via DGRAM precisa de `com.apple.security.network.server` além de `network.client` (a resposta ICMP é tráfego de entrada). Não validei App Store Review: Apple pode questionar `network.server` num app que não escuta portas; ter o TCP fallback pronto como plano B é obrigatório se a revisão recusar. Distribuição fora da loja (Developer ID, notarizado, sem sandbox) não tem essa restrição.

## Decisão de implementação sugerida (OpenWifi)

1. Gateway/interface: `SCDynamicStore` + notificação; `NWPathMonitor` só como gatilho.
2. Latência: ICMP DGRAM (id aleatório, filtro id+seq, timeout 1 s); em falha por timeout, tentar TCP (443 destino de internet; 80/443/53 gateway) e rotular "RTT TCP"; `sendto` errno 65/51 = "sem rota".
3. Tráfego: `IFMIB_IFDATA` 64-bit com fallback getifaddrs 32-bit com wrap; detectar reset por contador decrescente ou mudança de ifindex.
4. Entitlements se sandboxed: `network.client` + `network.server`; senão distribuir sem sandbox (Developer ID).

## Fora do escopo/não verificado

- Troca real de rede/gateway (Wi-Fi off) e disparo do `NWPathMonitor`.
- Host que bloqueia ICMP de verdade (usado blackhole 192.0.2.1 como substituto).
- Revisão da App Store com `network.server`; `ifi_lastchange`; IPv6/ICMPv6; Wi-Fi como interface primária (a máquina de teste usa Ethernet).
